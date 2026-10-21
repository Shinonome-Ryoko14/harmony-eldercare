import { BusinessError, usbManager } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { Constants } from '../common/Constants';

/** 串口日志类别 */
export enum SerialLogKind {
  INFO = 0,
  TX = 1,
  RX = 2,
  ERROR = 3
}

/** 一条串口日志 */
export interface SerialLogEntry {
  id: number;
  kind: number;
  text: string;
  ts: number;
}

/** 可供界面选择的 USB 串口设备 */
export interface UsbPortInfo {
  /** 设备唯一名（来自 USBDevice.name） */
  key: string;
  /** 展示名称，例如 "CH340 (1-1)" */
  label: string;
  vendorId: number;
  productId: number;
}

export type SerialLogListener = (logs: SerialLogEntry[]) => void;

/**
 * CH340 USB 转串口驱动（手机作为 USB Host）。
 *
 * 手机侧不能用 @ohos.usbManager.serial（仅 PC/2in1 支持），因此直接使用
 * @ohos.usbManager 的原始 USB 能力 + CH340 厂商控制请求：
 *   0x5F 读版本 / 0xA1 初始化 / 0x9A 写寄存器（波特率、LCR、流控）/ 0xA4 设置 DTR/RTS
 * 波特率算法与 Linux 内核 drivers/usb/serial/ch341.c 保持一致。
 *
 * 命令按“原样”发送，不追加 \r\n；开发板回显通过 bulk IN 端点轮询读取。
 */
export class UsbSerialService {
  private static instance: UsbSerialService | null = null;

  private pipe: usbManager.USBDevicePipe | null = null;
  private iface: usbManager.USBInterface | null = null;
  private inEp: usbManager.USBEndpoint | null = null;
  private outEp: usbManager.USBEndpoint | null = null;
  private device: usbManager.USBDevice | null = null;
  private deviceCache: usbManager.USBDevice[] = [];
  private running: boolean = false;
  private connected: boolean = false;
  private baudRate: number = Constants.SERIAL_DEFAULT_BAUD;
  private chipVersion: number = 0;
  private logs: SerialLogEntry[] = [];
  private logSeq: number = 0;
  private listeners: SerialLogListener[] = [];
  private readErrors: number = 0;

  static get(): UsbSerialService {
    if (UsbSerialService.instance === null) {
      UsbSerialService.instance = new UsbSerialService();
    }
    return UsbSerialService.instance;
  }

  // ==================== 端口枚举与权限 ====================

  /** 枚举当前可用的 USB 转串口设备 */
  listPorts(): UsbPortInfo[] {
    let result: UsbPortInfo[] = [];
    try {
      let devices: usbManager.USBDevice[] = usbManager.getDevices();
      this.deviceCache = devices;
      for (let i: number = 0; i < devices.length; i++) {
        let d: usbManager.USBDevice = devices[i];
        if (!UsbSerialService.hasBulkPair(d) && d.vendorId !== Constants.CH340_VENDOR_ID) {
          continue;
        }
        let name: string = d.productName !== undefined && d.productName.length > 0
          ? d.productName as string : 'USB 串口设备';
        if (d.vendorId === Constants.CH340_VENDOR_ID) {
          name = name.length > 0 ? `${name} · CH340` : 'CH340';
        }
        result.push({
          key: d.name,
          label: `${name} (${d.name})`,
          vendorId: d.vendorId,
          productId: d.productId
        });
      }
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      this.appendLog(SerialLogKind.ERROR, `枚举 USB 设备失败：${err.message}`);
    }
    return result;
  }

  /** 打开指定端口并初始化 CH340 */
  async openPort(key: string, baud: number): Promise<boolean> {
    this.close();
    let target: usbManager.USBDevice | null = null;
    for (let i: number = 0; i < this.deviceCache.length; i++) {
      if (this.deviceCache[i].name === key) {
        target = this.deviceCache[i];
        break;
      }
    }
    if (target === null) {
      this.appendLog(SerialLogKind.ERROR, '未找到该 USB 设备，请重新刷新设备列表');
      return false;
    }

    let device: usbManager.USBDevice = target;
    this.baudRate = baud;
    this.appendLog(SerialLogKind.INFO, `正在连接 ${device.name} ...`);

    try {
      let granted: boolean = await usbManager.requestRight(device.name);
      if (!granted) {
        this.appendLog(SerialLogKind.ERROR, '用户拒绝了 USB 访问权限');
        return false;
      }
      let pipe: usbManager.USBDevicePipe = usbManager.connectDevice(device);
      if (pipe === undefined || pipe === null) {
        this.appendLog(SerialLogKind.ERROR, '打开 USB 设备失败');
        return false;
      }
      this.pipe = pipe;
      this.device = device;

      if (!this.locateEndpoints(device)) {
        this.appendLog(SerialLogKind.ERROR, '未找到可用的串口收发端点');
        this.close();
        return false;
      }

      let iface: usbManager.USBInterface | null = this.iface;
      if (iface === null) {
        this.close();
        return false;
      }
      let claimRet: number = usbManager.claimInterface(pipe, iface, true);
      if (claimRet !== 0) {
        this.appendLog(SerialLogKind.ERROR, `占用串口接口失败（错误码 ${claimRet}）`);
        this.close();
        return false;
      }

      this.appendLog(SerialLogKind.INFO, `USB 设备已连接，串口参数 ${baud} 8N1`);
      await this.ch341Init(baud);

      this.running = true;
      this.connected = true;
      this.readErrors = 0;
      this.readLoop().catch((e: BusinessError) => {
        console.error(`串口读取循环异常: ${e.message}`);
      });
      return true;
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      this.appendLog(SerialLogKind.ERROR, `连接失败：${err.message}`);
      this.close();
      return false;
    }
  }

  /** 关闭串口并释放 USB 资源 */
  close(): void {
    let wasOpen: boolean = this.connected || this.pipe !== null;
    this.running = false;
    this.connected = false;
    let pipe: usbManager.USBDevicePipe | null = this.pipe;
    let iface: usbManager.USBInterface | null = this.iface;
    if (pipe !== null) {
      try {
        if (iface !== null) {
          usbManager.releaseInterface(pipe, iface);
        }
      } catch (e) {
        // 忽略释放失败，继续关闭通道
      }
      try {
        usbManager.closePipe(pipe);
      } catch (e) {
        // 关闭通道失败通常是设备已拔出
      }
    }
    this.pipe = null;
    this.iface = null;
    this.inEp = null;
    this.outEp = null;
    this.device = null;
    if (wasOpen) {
      this.appendLog(SerialLogKind.INFO, '串口已断开');
    }
  }

  isConnected(): boolean {
    return this.connected;
  }

  getBaudRate(): number {
    return this.baudRate;
  }

  getChipVersion(): number {
    return this.chipVersion;
  }

  // ==================== 收发 ====================

  /** 原样发送命令（不追加任何行尾） */
  async writeText(text: string): Promise<boolean> {
    let pipe: usbManager.USBDevicePipe | null = this.pipe;
    let ep: usbManager.USBEndpoint | null = this.outEp;
    if (!this.connected || pipe === null || ep === null) {
      this.appendLog(SerialLogKind.ERROR, '串口未连接，无法发送');
      return false;
    }
    if (text.length === 0) {
      return false;
    }
    let bytes: Uint8Array;
    try {
      bytes = new util.TextEncoder().encodeInto(text);
    } catch (e) {
      this.appendLog(SerialLogKind.ERROR, '命令编码失败');
      return false;
    }
    let chunk: number = ep.maxPacketSize > 0 ? ep.maxPacketSize : 32;
    let offset: number = 0;
    try {
      while (offset < bytes.length) {
        let end: number = offset + chunk < bytes.length ? offset + chunk : bytes.length;
        let part: Uint8Array = bytes.slice(offset, end);
        let sent: number = await usbManager.bulkTransfer(pipe, ep, part, 2000);
        if (sent < 0) {
          this.appendLog(SerialLogKind.ERROR, 'USB 发送失败');
          return false;
        }
        offset = end;
      }
      this.appendLog(SerialLogKind.TX, text);
      return true;
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      this.appendLog(SerialLogKind.ERROR, `发送失败：${err.message}`);
      return false;
    }
  }

  /** 已连接时按新波特率重新配置 CH340 */
  async setBaudRate(baud: number): Promise<void> {
    this.baudRate = baud;
    if (this.connected) {
      await this.ch341Init(baud);
      this.appendLog(SerialLogKind.INFO, `波特率已切换为 ${baud}`);
    }
  }

  private async readLoop(): Promise<void> {
    while (this.running) {
      let pipe: usbManager.USBDevicePipe | null = this.pipe;
      let ep: usbManager.USBEndpoint | null = this.inEp;
      if (pipe === null || ep === null) {
        break;
      }
      let buffer: Uint8Array = new Uint8Array(Constants.SERIAL_READ_BUFFER);
      try {
        let size: number = await usbManager.bulkTransfer(pipe, ep, buffer, 300);
        if (size > 0) {
          this.readErrors = 0;
          let data: Uint8Array = buffer.slice(0, size);
          this.appendLog(SerialLogKind.RX, UsbSerialService.decode(data));
        } else {
          await UsbSerialService.sleep(60);
        }
      } catch (e) {
        // 读超时是正常现象，不刷屏；连续失败时稍作等待
        this.readErrors = this.readErrors + 1;
        if (this.readErrors === 1) {
          let err: BusinessError = e as BusinessError;
          if (err !== undefined && err.message !== undefined) {
            console.info(`串口读取等待中: ${err.message}`);
          }
        }
        await UsbSerialService.sleep(this.readErrors > 5 ? 300 : 80);
      }
    }
  }

  private static decode(data: Uint8Array): string {
    try {
      let decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      return decoder.decodeWithStream(data, { stream: false });
    } catch (e) {
      let text: string = '';
      for (let i: number = 0; i < data.length; i++) {
        let code: number = data[i];
        if (code >= 32 && code < 127) {
          text += String.fromCharCode(code);
        }
      }
      return text;
    }
  }

  // ==================== CH340 协议 ====================

  private async ch341Init(baud: number): Promise<void> {
    let ver: Uint8Array | null = await this.ctrlIn(0x5F, 0, 0, 2);
    if (ver !== null && ver.length > 0) {
      this.chipVersion = ver[0];
    } else {
      this.chipVersion = 0;
    }
    this.appendLog(SerialLogKind.INFO, `CH340 芯片版本：0x${UsbSerialService.hex(this.chipVersion)}`);

    // 沁恒 CH340 常用初始化序列（8N1，参考 WCH 驱动/lib-ch340 实现）
    await this.ctrlOut(0xA1, 0x0000, 0x0000);
    await this.ctrlOut(0x9A, 0x2518, 0x0050);
    await this.ctrlOut(0xA1, 0x501F, 0xD90A);
    await this.applyBaud(baud);
    // 不主动拉高 DTR/RTS，避免部分开发板把这两个信号接到复位/BOOT 引脚
    await this.ctrlOut(0xA4, 0xFFFF, 0);
    // 关闭硬件流控
    await this.ctrlOut(0x9A, 0x2727, 0x0000);
  }

  private async applyBaud(baud: number): Promise<void> {
    let params: number[] | null = UsbSerialService.ch340BaudParams(baud);
    if (params === null) {
      this.appendLog(SerialLogKind.ERROR, `暂不支持 ${baud} 波特率，已保持芯片默认设置`);
      return;
    }
    await this.ctrlOut(0x9A, 0x1312, params[0]);
    await this.ctrlOut(0x9A, 0x0F2C, params[1]);
  }

  /** CH340 常用波特率寄存器值（高 16 位写 0x1312，低 16 位写 0x0F2C） */
  private static ch340BaudParams(baud: number): number[] | null {
    if (baud === 2400) {
      return [0xD901, 0x0038];
    }
    if (baud === 4800) {
      return [0x6402, 0x001F];
    }
    if (baud === 9600) {
      return [0xB202, 0x0013];
    }
    if (baud === 19200) {
      return [0xD902, 0x000D];
    }
    if (baud === 38400) {
      return [0x6403, 0x000A];
    }
    if (baud === 115200) {
      return [0xCC03, 0x0008];
    }
    return null;
  }

  private async ctrlOut(request: number, value: number, index: number): Promise<number> {
    let pipe: usbManager.USBDevicePipe | null = this.pipe;
    if (pipe === null) {
      return -1;
    }
    let params: usbManager.USBDeviceRequestParams = {
      bmRequestType: 0x40,
      bRequest: request,
      wValue: value & 0xFFFF,
      wIndex: index & 0xFFFF,
      wLength: 0,
      data: new Uint8Array(0)
    };
    try {
      return await usbManager.usbControlTransfer(pipe, params, 1000);
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error(`CH340 控制写失败(0x${UsbSerialService.hex(request)}): ${err.message}`);
      return -1;
    }
  }

  private async ctrlIn(request: number, value: number, index: number,
    length: number): Promise<Uint8Array | null> {
    let pipe: usbManager.USBDevicePipe | null = this.pipe;
    if (pipe === null) {
      return null;
    }
    let data: Uint8Array = new Uint8Array(length);
    let params: usbManager.USBDeviceRequestParams = {
      bmRequestType: 0xC0,
      bRequest: request,
      wValue: value & 0xFFFF,
      wIndex: index & 0xFFFF,
      wLength: length,
      data: data
    };
    try {
      await usbManager.usbControlTransfer(pipe, params, 1000);
      return data;
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error(`CH340 控制读失败(0x${UsbSerialService.hex(request)}): ${err.message}`);
      return null;
    }
  }

  // ==================== 端点定位 ====================

  private locateEndpoints(device: usbManager.USBDevice): boolean {
    let configs: usbManager.USBConfiguration[] = device.configs;
    for (let c: number = 0; c < configs.length; c++) {
      let interfaces: usbManager.USBInterface[] = configs[c].interfaces;
      for (let i: number = 0; i < interfaces.length; i++) {
        let iface: usbManager.USBInterface = interfaces[i];
        let out: usbManager.USBEndpoint | null = null;
        let input: usbManager.USBEndpoint | null = null;
        let eps: usbManager.USBEndpoint[] = iface.endpoints;
        for (let e: number = 0; e < eps.length; e++) {
          let ep: usbManager.USBEndpoint = eps[e];
          let bulk: boolean = ep.attributes === 2;
          if (!bulk) {
            continue;
          }
          let isIn: boolean = ep.direction === 128 || ep.address >= 128;
          if (isIn) {
            input = ep;
          } else {
            out = ep;
          }
        }
        if (out !== null && input !== null) {
          this.iface = iface;
          this.outEp = out;
          this.inEp = input;
          return true;
        }
      }
    }
    return false;
  }

  private static hasBulkPair(device: usbManager.USBDevice): boolean {
    let configs: usbManager.USBConfiguration[] = device.configs;
    for (let c: number = 0; c < configs.length; c++) {
      let interfaces: usbManager.USBInterface[] = configs[c].interfaces;
      for (let i: number = 0; i < interfaces.length; i++) {
        let eps: usbManager.USBEndpoint[] = interfaces[i].endpoints;
        let hasOut: boolean = false;
        let hasIn: boolean = false;
        for (let e: number = 0; e < eps.length; e++) {
          let ep: usbManager.USBEndpoint = eps[e];
          let bulk: boolean = ep.attributes === 2;
          if (!bulk) {
            continue;
          }
          if (ep.direction === 128 || ep.address >= 128) {
            hasIn = true;
          } else {
            hasOut = true;
          }
        }
        if (hasIn && hasOut) {
          return true;
        }
      }
    }
    return false;
  }

  // ==================== 日志 ====================

  subscribe(listener: SerialLogListener): void {
    this.listeners.push(listener);
  }

  unsubscribe(listener: SerialLogListener): void {
    let idx: number = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  getLogs(): SerialLogEntry[] {
    return this.logs.slice(0, this.logs.length);
  }

  clearLogs(): void {
    this.logs = [];
    this.emit();
  }

  private appendLog(kind: number, text: string): void {
    this.logSeq = this.logSeq + 1;
    this.logs.push({
      id: this.logSeq,
      kind: kind,
      text: text,
      ts: Date.now()
    });
    if (this.logs.length > Constants.SERIAL_LOG_MAX) {
      this.logs.splice(0, this.logs.length - Constants.SERIAL_LOG_MAX);
    }
    this.emit();
  }

  private emit(): void {
    let copy: SerialLogEntry[] = this.logs.slice(0, this.logs.length);
    this.listeners.forEach((l: SerialLogListener) => {
      l(copy);
    });
  }

  private static hex(n: number): string {
    let s: string = n.toString(16).toUpperCase();
    return s.length < 2 ? `0${s}` : s;
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }
}
