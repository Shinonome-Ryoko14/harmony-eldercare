import socket from '@ohos.net.socket';
import util from '@ohos.util';
import { BusinessError } from '@ohos.base';
import { Constants } from '../common/Constants';
import { Protocol } from '../common/Protocol';
import { DeviceData } from '../common/Types';
import { AppStore } from '../store/AppStore';
import { Repository } from '../data/Repository';
import { AlertDraft, RuleEngine, RuleResult } from '../data/RuleEngine';

/**
 * UDP 通信服务：
 * 1) 周期性向局域网广播探测包（硬件收到后回发数据）
 * 2) 监听 8888 端口，解析报文并按来源 IP 识别设备
 * 3) 定时巡检，判定设备在线状态并触发周期性告警
 */
export class UdpService {
  private static instance: UdpService | null = null;
  private udp: socket.UDPSocket | null = null;
  private probeTimer: number = -1;
  private tickTimer: number = -1;
  private started: boolean = false;

  static get(): UdpService {
    if (UdpService.instance === null) {
      UdpService.instance = new UdpService();
    }
    return UdpService.instance;
  }

  isRunning(): boolean {
    return this.started;
  }

  /** 启动 UDP 服务 */
  async start(): Promise<void> {
    if (this.started) {
      return;
    }
    let udp: socket.UDPSocket = socket.constructUDPSocketInstance();
    let bindOptions: socket.UDPBindOptions = {
      address: Constants.BIND_ADDR,
      port: Constants.UDP_PORT
    };
    await udp.bind(bindOptions);
    let extra: socket.UDPExtraOptions = { broadcast: true };
    await udp.setExtraOptions(extra);
    udp.on('message', (info: socket.SocketMessageInfo) => {
      this.onMessage(info);
    });
    udp.on('error', (err: BusinessError) => {
      console.error(`UDP 错误: ${JSON.stringify(err)}`);
    });
    this.udp = udp;
    this.started = true;

    this.sendProbe();
    this.probeTimer = setInterval(() => {
      this.sendProbe();
    }, Constants.PROBE_INTERVAL);
    this.tickTimer = setInterval(() => {
      this.tick();
    }, 1000);
  }

  stop(): void {
    if (this.probeTimer !== -1) {
      clearInterval(this.probeTimer);
      this.probeTimer = -1;
    }
    if (this.tickTimer !== -1) {
      clearInterval(this.tickTimer);
      this.tickTimer = -1;
    }
    if (this.udp !== null) {
      try {
        this.udp.off('message');
        this.udp.close();
      } catch (e) {
        console.error(`关闭 UDP 失败: ${JSON.stringify(e)}`);
      }
      this.udp = null;
    }
    this.started = false;
  }

  /** 发送探测包（广播） */
  async sendProbe(): Promise<void> {
    if (this.udp === null) {
      return;
    }
    let options: socket.UDPSendOptions = {
      data: Constants.PROBE_PACKET,
      address: Constants.BROADCAST_ADDR,
      port: Constants.UDP_PORT
    };
    try {
      await this.udp.send(options);
    } catch (e) {
      console.error(`探测包发送失败: ${JSON.stringify(e)}`);
    }
  }

  /** 主动向指定 IP 发送探测（用于手动连接） */
  async probeIp(ip: string): Promise<void> {
    if (this.udp === null) {
      return;
    }
    let options: socket.UDPSendOptions = {
      data: Constants.PROBE_PACKET,
      address: ip,
      port: Constants.UDP_PORT
    };
    try {
      await this.udp.send(options);
    } catch (e) {
      console.error(`定向探测失败: ${JSON.stringify(e)}`);
    }
  }

  private decode(buffer: ArrayBuffer): string {
    let decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
    let ret: string = decoder.decodeWithStream(new Uint8Array(buffer), { stream: false });
    return ret;
  }

  private onMessage(info: socket.SocketMessageInfo): void {
    let ip: string = info.remoteInfo.address;
    let text: string = this.decode(info.message);
    const data: DeviceData | null = Protocol.parse(ip, text);
    if (data === null) {
      return;
    }
    let store: AppStore = AppStore.get();
    let prev: DeviceData | undefined = store.getDevice(ip);
    if (prev !== undefined && prev.lastActive > 0) {
      data.lastActive = prev.lastActive;
    }

    let result: RuleResult = RuleEngine.get().process(data);
    store.upsert(data);

    if (result.activityCount > 0) {
      Repository.addActivity(ip, data.lastSeen, result.activityCount);
    }
    result.alerts.forEach((a: AlertDraft) => {
      Repository.addAlert(ip, a, data.lastSeen);
    });
  }

  private async tick(): Promise<void> {
    let now: number = Date.now();
    let store: AppStore = AppStore.get();
    let devices: DeviceData[] = store.getDevices();
    for (let i: number = 0; i < devices.length; i++) {
      let d: DeviceData = devices[i];
      if (d.online && now - d.lastSeen > Constants.OFFLINE_TIMEOUT) {
        store.markOffline(d.ip);
        await Repository.addAlert(d.ip, RuleEngine.get().offlineAlert(), now);
        continue;
      }
      if (d.online) {
        let periodic: AlertDraft[] = RuleEngine.get().checkPeriodic(d);
        for (let j: number = 0; j < periodic.length; j++) {
          await Repository.addAlert(d.ip, periodic[j], now);
        }
      }
    }
  }
}
