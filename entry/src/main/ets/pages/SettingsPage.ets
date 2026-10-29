import { Theme } from '../common/Theme';
import { DateUtil } from '../common/Protocol';
import { Constants } from '../common/Constants';
import { ConfigStore } from '../store/ConfigStore';
import { SerialLogEntry, SerialLogKind, SerialLogListener, UsbPortInfo, UsbSerialService } from '../network/UsbSerialService';
import { AiConfigPanel } from '../components/AiConfigPanel';

const BAUD_RATES: number[] = [2400, 4800, 9600, 19200, 38400, 115200];

function baudOptions(): SelectOption[] {
  let list: SelectOption[] = [];
  for (let i: number = 0; i < BAUD_RATES.length; i++) {
    list.push({ value: `${BAUD_RATES[i]} bps` });
  }
  return list;
}

function indexOfBaud(baud: number): number {
  for (let i: number = 0; i < BAUD_RATES.length; i++) {
    if (BAUD_RATES[i] === baud) {
      return i;
    }
  }
  return 5;
}

/**
 * 设备设置页：
 * - USB OTG + CH340 串口连接（波特率可调，默认 115200）
 * - WiFi / 上报地址 / uart0 等设备命令
 * - 串口控制台（发送与回显）
 */
@Component
export struct SettingsPage {
  @State ports: UsbPortInfo[] = [];
  @State portIndex: number = 0;
  @State baudRate: number = Constants.SERIAL_DEFAULT_BAUD;
  @State baudIndex: number = 5;
  @State connected: boolean = false;
  @State busy: boolean = false;
  @State chipVersion: string = '';
  @State ssid: string = '';
  @State password: string = '';
  @State deviceUrl: string = '';
  @State rawCmd: string = '';
  @State logs: SerialLogEntry[] = [];
  private logScroller: Scroller = new Scroller();
  private waitingUrl: boolean = false;
  private rxBuffer: string = '';

  private logListener: SerialLogListener = (logs: SerialLogEntry[]) => {
    this.logs = logs;
    if (logs.length > 0) {
      let last: SerialLogEntry = logs[logs.length - 1];
      if (last.kind === SerialLogKind.RX && this.waitingUrl) {
        this.rxBuffer = this.rxBuffer + last.text;
        let url: string = this.extractUrl(this.rxBuffer);
        if (url.length > 0) {
          this.deviceUrl = url;
          this.waitingUrl = false;
          ConfigStore.saveDeviceUrl(url);
        }
      }
    }
    setTimeout(() => {
      try {
        this.logScroller.scrollEdge(Edge.Bottom);
      } catch (e) {
        // 滚动失败不影响日志展示
      }
    }, 60);
  };

  aboutToAppear(): void {
    this.baudRate = ConfigStore.getBaudRate();
    this.baudIndex = indexOfBaud(this.baudRate);
    this.baudRate = BAUD_RATES[this.baudIndex];
    let savedUrl: string = ConfigStore.getDeviceUrl();
    this.deviceUrl = savedUrl.length > 0 ? savedUrl : ConfigStore.baseUrl();
    this.connected = UsbSerialService.get().isConnected();
    if (this.connected) {
      this.baudRate = UsbSerialService.get().getBaudRate();
      this.baudIndex = indexOfBaud(this.baudRate);
      this.baudRate = BAUD_RATES[this.baudIndex];
      this.chipVersion = UsbSerialService.get().getChipVersion().toString(16).toUpperCase();
    }
    this.ports = UsbSerialService.get().listPorts();
    if (this.portIndex >= this.ports.length) {
      this.portIndex = 0;
    }
    UsbSerialService.get().subscribe(this.logListener);
    this.logs = UsbSerialService.get().getLogs();
  }

  aboutToDisappear(): void {
    UsbSerialService.get().unsubscribe(this.logListener);
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (err) {
      console.error(`提示弹出失败: ${JSON.stringify(err)}`);
    }
  }

  private portOptions(): SelectOption[] {
    let list: SelectOption[] = [];
    for (let i: number = 0; i < this.ports.length; i++) {
      list.push({ value: this.ports[i].label });
    }
    if (list.length === 0) {
      list.push({ value: '未发现 USB 串口设备' });
    }
    return list;
  }

  private portLabel(): string {
    if (this.ports.length === 0) {
      return '未发现 USB 串口设备';
    }
    return this.ports[this.portIndex > 0 && this.portIndex < this.ports.length ? this.portIndex : 0].label;
  }

  private refreshPorts(): void {
    this.ports = UsbSerialService.get().listPorts();
    if (this.portIndex >= this.ports.length) {
      this.portIndex = 0;
    }
    this.toast(this.ports.length > 0 ? `发现 ${this.ports.length} 个串口设备` : '未发现 USB 串口设备');
  }

  private async openPort(): Promise<void> {
    if (this.ports.length === 0) {
      this.toast('请先插入开发板并刷新设备列表');
      return;
    }
    this.busy = true;
    let idx: number = this.portIndex >= 0 && this.portIndex < this.ports.length ? this.portIndex : 0;
    let ok: boolean = await UsbSerialService.get().openPort(this.ports[idx].key, this.baudRate);
    this.busy = false;
    this.connected = UsbSerialService.get().isConnected();
    if (ok) {
      this.chipVersion = UsbSerialService.get().getChipVersion().toString(16).toUpperCase();
      this.toast(`串口已连接（${this.baudRate}）`);
    } else {
      this.toast('连接失败，请查看下方串口日志');
    }
  }

  private disconnect(): void {
    UsbSerialService.get().close();
    this.connected = false;
    this.chipVersion = '';
    this.toast('串口已断开');
  }

  private async changeBaud(index: number): Promise<void> {
    if (index < 0 || index >= BAUD_RATES.length) {
      return;
    }
    this.baudIndex = index;
    this.baudRate = BAUD_RATES[index];
    await ConfigStore.saveBaudRate(this.baudRate);
    if (this.connected) {
      await UsbSerialService.get().setBaudRate(this.baudRate);
      this.toast(`波特率已切换为 ${this.baudRate}`);
    }
  }

  private async sendText(cmd: string): Promise<void> {
    if (!this.connected) {
      this.toast('请先连接 USB 串口');
      return;
    }
    if (cmd.length === 0) {
      this.toast('命令不能为空');
      return;
    }
    let ok: boolean = await UsbSerialService.get().writeText(cmd);
    if (!ok) {
      this.toast('发送失败，请查看串口日志');
    }
  }

  private async sendWifi(): Promise<void> {
    let name: string = this.ssid.trim();
    if (name.length === 0) {
      this.toast('请输入 WiFi 名称');
      return;
    }
    if (this.password.length === 0) {
      this.toast('请输入 WiFi 密码');
      return;
    }
    // 固件格式：wifi set 名称 密码（允许空格，不加引号）
    await this.sendText(`wifi set ${name} ${this.password}`);
  }

  private normalizeUrl(): string {
    return this.deviceUrl.trim();
  }

  private urlValid(url: string): boolean {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      this.toast('地址必须以 http:// 开头');
      return false;
    }
    let idx: number = url.indexOf('://');
    let rest: string = url.substring(idx + 3);
    let colon: number = rest.indexOf(':');
    let slash: number = rest.indexOf('/');
    if (colon < 0 || (slash >= 0 && colon > slash)) {
      this.toast('地址需要包含端口，如 http://10.19.81.90:8000');
      return false;
    }
    return true;
  }

  /** 从设备回显中提取 http(s) 地址 */
  private extractUrl(text: string): string {
    let idxHttp: number = text.indexOf('http://');
    let idxHttps: number = text.indexOf('https://');
    let idx: number = -1;
    if (idxHttp >= 0 && idxHttps >= 0) {
      idx = idxHttp < idxHttps ? idxHttp : idxHttps;
    } else if (idxHttp >= 0) {
      idx = idxHttp;
    } else if (idxHttps >= 0) {
      idx = idxHttps;
    }
    if (idx < 0) {
      return '';
    }
    let rest: string = text.substring(idx);
    let end: number = rest.length;
    for (let i: number = 0; i < rest.length; i++) {
      let c: string = rest.charAt(i);
      if (c === ' ' || c === '\r' || c === '\n' || c === '\t' || c === '"' || c === '\'') {
        end = i;
        break;
      }
    }
    return rest.substring(0, end);
  }

  private async queryUrl(): Promise<void> {
    this.rxBuffer = '';
    this.waitingUrl = true;
    await this.sendText('url show');
    setTimeout(() => {
      this.waitingUrl = false;
    }, 3000);
  }

  private async setUrl(): Promise<void> {
    let url: string = this.normalizeUrl();
    if (!this.urlValid(url)) {
      return;
    }
    await this.sendText(`url set ${url}`);
    await ConfigStore.saveDeviceUrl(url);
  }

  private async clearUrl(): Promise<void> {
    await this.sendText('url clear');
    await ConfigStore.saveDeviceUrl('');
    this.deviceUrl = '';
    this.toast('已发送 url clear，当前地址以设备回显为准');
    await this.sleep(300);
    await this.queryUrl();
  }

  private async sendRaw(): Promise<void> {
    let cmd: string = this.rawCmd;
    if (cmd.length === 0) {
      this.toast('请输入命令');
      return;
    }
    await this.sendText(cmd);
  }

  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  private logColor(kind: number): string {
    if (kind === SerialLogKind.TX) {
      return Theme.PRIMARY_DARK;
    }
    if (kind === SerialLogKind.RX) {
      return Theme.TEXT;
    }
    if (kind === SerialLogKind.ERROR) {
      return Theme.DANGER;
    }
    return Theme.SUB;
  }

  private logPrefix(kind: number): string {
    if (kind === SerialLogKind.TX) {
      return 'TX';
    }
    if (kind === SerialLogKind.RX) {
      return 'RX';
    }
    if (kind === SerialLogKind.ERROR) {
      return 'ERR';
    }
    return 'SYS';
  }

  @Builder
  cardTitle(title: string, hint: string) {
    Row() {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TEXT)
      Text(hint)
        .fontSize(11)
        .fontColor(Theme.SUB)
        .margin({ left: 8 })
        .layoutWeight(1)
    }
    .width('100%')
  }

  @Builder
  aiCard() {
    Column({ space: 10 }) {
      this.cardTitle('AI 管家模型', '免费模型 · OpenAI 兼容')
      AiConfigPanel({
        onSaved: () => {
          this.toast('AI 配置已保存');
        }
      })
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Theme.CARD)
    .borderRadius(16)
    .border({ width: 1, color: Theme.HAIRLINE })
    .shadow({ radius: 14, color: Theme.SHADOW, offsetX: 0, offsetY: 4 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  usbCard() {
    Column({ space: 10 }) {
      this.cardTitle('USB 串口', 'OTG 连接开发板')
      Row() {
        Text('设备')
          .fontSize(13)
          .fontColor(Theme.SUB)
          .width(52)
        Select(this.portOptions())
          .selected(this.portIndex)
          .value(this.portLabel())
          .layoutWeight(1)
          .font({ size: 13 })
          .onSelect((index: number) => {
            this.portIndex = index;
          })
        Button('刷新')
          .height(34)
          .fontSize(12)
          .backgroundColor(Theme.PRIMARY_SOFT)
          .fontColor(Theme.PRIMARY)
          .margin({ left: 8 })
          .onClick(() => {
            this.refreshPorts();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        Text('波特率')
          .fontSize(13)
          .fontColor(Theme.SUB)
          .width(52)
        Select(baudOptions())
          .selected(this.baudIndex)
          .value(`${this.baudRate} bps`)
          .layoutWeight(1)
          .font({ size: 13 })
          .onSelect((index: number) => {
            this.changeBaud(index);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 10 }) {
        Button(this.busy ? '连接中...' : (this.connected ? '重新连接' : '连接串口'))
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .enabled(!this.busy)
          .backgroundColor(Theme.PRIMARY)
          .onClick(() => {
            this.openPort();
          })
        Button('断开')
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .enabled(this.connected)
          .backgroundColor(Theme.DANGER_SOFT)
          .fontColor(Theme.DANGER)
          .onClick(() => {
            this.disconnect();
          })
      }
      .width('100%')

      Row() {
        Column()
          .width(8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(this.connected ? Theme.OK : Theme.SUB)
        Text(this.connected
          ? `已连接 · ${this.baudRate} bps${this.chipVersion.length > 0 ? ` · 芯片版本 0x${this.chipVersion}` : ''}`
          : '未连接')
          .fontSize(12)
          .fontColor(this.connected ? Theme.OK : Theme.SUB)
          .margin({ left: 6 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text('提示：每次重新插拔 USB 后需要重新授权；命令按原样发送，不追加换行。')
        .fontSize(11)
        .fontColor(Theme.SUB)
        .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Theme.CARD)
    .borderRadius(16)
    .border({ width: 1, color: Theme.HAIRLINE })
    .shadow({ radius: 14, color: Theme.SHADOW, offsetX: 0, offsetY: 4 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  wifiCard() {
    Column({ space: 10 }) {
      this.cardTitle('WiFi 设置', 'wifi set 名称 密码')
      Row() {
        Text('名称')
          .fontSize(13)
          .fontColor(Theme.SUB)
          .width(52)
        TextInput({ placeholder: 'WiFi 名称（SSID）', text: this.ssid })
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .backgroundColor(Theme.INPUT)
          .borderRadius(10)
          .onChange((v: string) => {
            this.ssid = v;
          })
      }
      .width('100%')

      Row() {
        Text('密码')
          .fontSize(13)
          .fontColor(Theme.SUB)
          .width(52)
        TextInput({ placeholder: 'WiFi 密码', text: this.password })
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .backgroundColor(Theme.INPUT)
          .borderRadius(10)
          .type(InputType.Password)
          .showPasswordIcon(true)
          .onChange((v: string) => {
            this.password = v;
          })
      }
      .width('100%')

      Button('发送 WiFi 设置命令')
        .width('100%')
        .height(38)
        .fontSize(14)
        .backgroundColor(Theme.PRIMARY)
        .onClick(() => {
          this.sendWifi();
        })

      Text('名称与密码允许空格，APP 会把 “wifi set 名称 密码” 原样发送；若固件按空格拆分，请使用下方原始命令框调整。')
        .fontSize(11)
        .fontColor(Theme.SUB)
        .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Theme.CARD)
    .borderRadius(16)
    .border({ width: 1, color: Theme.HAIRLINE })
    .shadow({ radius: 14, color: Theme.SHADOW, offsetX: 0, offsetY: 4 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  urlCard() {
    Column({ space: 10 }) {
      this.cardTitle('上报地址', 'url show / set / clear')
      Row() {
        Text('地址')
          .fontSize(13)
          .fontColor(Theme.SUB)
          .width(52)
        TextInput({ placeholder: 'http://10.19.81.90:8000', text: this.deviceUrl })
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .backgroundColor(Theme.INPUT)
          .borderRadius(10)
          .onChange((v: string) => {
            this.deviceUrl = v;
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        Button('查询')
          .layoutWeight(1)
          .height(36)
          .fontSize(13)
          .backgroundColor(Theme.PRIMARY_SOFT)
          .fontColor(Theme.PRIMARY)
          .onClick(() => {
            this.queryUrl();
          })
        Button('设置')
          .layoutWeight(1)
          .height(36)
          .fontSize(13)
          .backgroundColor(Theme.PRIMARY)
          .onClick(() => {
            this.setUrl();
          })
        Button('恢复默认')
          .layoutWeight(1)
          .height(36)
          .fontSize(13)
          .backgroundColor(Theme.DANGER_SOFT)
          .fontColor(Theme.DANGER)
          .onClick(() => {
            this.clearUrl();
          })
      }
      .width('100%')

      Text('地址必须包含 http:// 和端口；恢复默认会发送 url clear，再自动查询当前地址。')
        .fontSize(11)
        .fontColor(Theme.SUB)
        .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Theme.CARD)
    .borderRadius(16)
    .border({ width: 1, color: Theme.HAIRLINE })
    .shadow({ radius: 14, color: Theme.SHADOW, offsetX: 0, offsetY: 4 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  consoleCard() {
    Column({ space: 10 }) {
      Row() {
        Text('串口控制台')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT)
        Text('TX / RX')
          .fontSize(11)
          .fontColor(Theme.SUB)
          .margin({ left: 8 })
          .layoutWeight(1)
        Text('清空')
          .fontSize(12)
          .fontColor(Theme.PRIMARY)
          .onClick(() => {
            UsbSerialService.get().clearLogs();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 8 }) {
        Button('发送 uart0')
          .height(34)
          .fontSize(12)
          .backgroundColor(Theme.PRIMARY_SOFT)
          .fontColor(Theme.PRIMARY)
          .onClick(() => {
            this.sendText('uart0');
          })
        Button('查询 url')
          .height(34)
          .fontSize(12)
          .backgroundColor(Theme.PRIMARY_SOFT)
          .fontColor(Theme.PRIMARY)
          .onClick(() => {
            this.queryUrl();
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        TextInput({ placeholder: '原始命令，例如 url show', text: this.rawCmd })
          .layoutWeight(1)
          .height(36)
          .fontSize(13)
          .backgroundColor(Theme.INPUT)
          .borderRadius(10)
          .onChange((v: string) => {
            this.rawCmd = v;
          })
        Button('发送')
          .height(36)
          .fontSize(13)
          .backgroundColor(Theme.PRIMARY)
          .onClick(() => {
            this.sendRaw();
          })
      }
      .width('100%')

      Scroll(this.logScroller) {
        Column({ space: 4 }) {
          if (this.logs.length === 0) {
            Text('暂无串口日志')
              .fontSize(12)
              .fontColor(Theme.SUB)
              .width('100%')
              .margin({ top: 8 })
          } else {
            ForEach(this.logs, (entry: SerialLogEntry) => {
              Row() {
                Text(DateUtil.time(entry.ts))
                  .fontSize(10)
                  .fontColor(Theme.SUB)
                  .width(52)
                Text(this.logPrefix(entry.kind))
                  .fontSize(10)
                  .fontColor(this.logColor(entry.kind))
                  .width(26)
                Text(entry.text)
                  .fontSize(12)
                  .fontColor(this.logColor(entry.kind))
                  .layoutWeight(1)
                  .textAlign(TextAlign.Start)
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
            }, (entry: SerialLogEntry) => `${entry.id}`)
          }
        }
        .width('100%')
        .padding(8)
      }
      .width('100%')
      .height(220)
      .backgroundColor(Theme.CHIP)
      .borderRadius(8)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Theme.CARD)
    .borderRadius(16)
    .border({ width: 1, color: Theme.HAIRLINE })
    .shadow({ radius: 14, color: Theme.SHADOW, offsetX: 0, offsetY: 4 })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Text('设备设置')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT)
          .width('100%')
        Text('AI 模型、USB 串口、WiFi 与数据上报地址')
          .fontSize(12)
          .fontColor(Theme.SUB)
          .width('100%')

        this.aiCard()
        this.usbCard()
        this.wifiCard()
        this.urlCard()
        this.consoleCard()
      }
      .padding(16)
      .width('100%')
    }
    .backgroundColor(Theme.BG)
    .width('100%')
    .height('100%')
  }
}
