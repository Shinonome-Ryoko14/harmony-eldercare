import { DeviceData, LatestRecord } from '../common/Types';
import { Constants } from '../common/Constants';
import { DateUtil } from '../common/Protocol';
import { Theme } from '../common/Theme';
import { AppStore, StoreListener } from '../store/AppStore';
import { ConfigStore } from '../store/ConfigStore';
import { HttpService } from '../network/HttpService';
import { InfoCard } from '../components/InfoCard';
import { AppIcon } from '../components/AppIcon';

const EMPTY_DEVICE: DeviceData = {
  deviceNo: 0,
  temp: 0,
  humi: 0,
  door: 0,
  radarPresence: 0,
  radarMotion: 0,
  sos: 0,
  alarm: 0,
  alarmType: '',
  lastSeen: 0,
  serverTs: 0,
  lastActive: 0,
  online: false
};

@Component
export struct RealtimePage {
  @State current: DeviceData = EMPTY_DEVICE;
  @State history: LatestRecord[] = [];
  @State fetchOk: boolean = false;
  @State fetchMsg: string = '未连接';
  @State showSettings: boolean = false;
  @State showDebug: boolean = false;
  @State hostInput: string = '';
  @State portInput: string = '';
  @State deviceInput: string = '';
  @State lastUpdate: number = 0;
  @State lastRaw: string = '';
  @State revision: number = 0;

  private listener: StoreListener = () => {
    let store: AppStore = AppStore.get();
    let cur: DeviceData | undefined = store.current();
    this.current = cur !== undefined ? cur : EMPTY_DEVICE;
    let history: LatestRecord[] = store.getHistory();
    this.history = history.slice(0, history.length);
    this.fetchOk = store.getFetchState().ok;
    this.fetchMsg = store.getFetchState().message;
    if (this.fetchOk) {
      this.lastUpdate = store.getLastUpdateTs();
    }
    this.lastRaw = store.getLastRaw();
    this.revision = store.getRevision();
  };

  aboutToAppear(): void {
    AppStore.get().subscribe(this.listener);
    this.listener(AppStore.get().getDevices());
    this.hostInput = ConfigStore.getHost();
    this.portInput = `${ConfigStore.getPort()}`;
    this.deviceInput = `${ConfigStore.getDeviceNo()}`;
  }

  aboutToDisappear(): void {
    AppStore.get().unsubscribe(this.listener);
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (err) {
      console.error(`提示弹出失败: ${JSON.stringify(err)}`);
    }
  }

  private tempAccent(): string {
    if (this.current.temp > Constants.TEMP_MAX || (this.current.temp < Constants.TEMP_MIN && this.current.temp !== 0)) {
      return Theme.WARN;
    }
    return Theme.PRIMARY;
  }

  private statusText(): string {
    return this.current.online ? '在线' : '离线';
  }

  private async saveConfig(): Promise<void> {
    let host: string = this.hostInput.trim();
    if (host.length === 0) {
      this.toast('请输入服务器 IP');
      return;
    }
    let port: number = Number.parseInt(this.portInput.trim());
    if (Number.isNaN(port) || port <= 0 || port > 65535) {
      this.toast('端口不合法（1-65535）');
      return;
    }
    let deviceNo: number = Number.parseInt(this.deviceInput.trim());
    if (Number.isNaN(deviceNo) || deviceNo < 0) {
      this.toast('设备号不合法');
      return;
    }
    try {
      await ConfigStore.save(host, port, deviceNo, ConfigStore.getPollMs());
      this.toast('已保存，正在重新连接...');
      this.showSettings = false;
      await HttpService.get().restart();
    } catch (e) {
      console.error(`配置保存失败: ${JSON.stringify(e)}`);
      this.toast('保存失败，请重试');
    }
  }

  @Builder
  settingsPanel() {
    Column({ space: 10 }) {
      Text('服务器设置')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TEXT)
        .width('100%')

      Row() {
        Text('IP')
          .fontSize(13)
          .fontColor(Theme.SUB)
          .width(56)
        TextInput({ placeholder: '如 10.19.81.90', text: this.hostInput })
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .backgroundColor(Theme.INPUT)
          .borderRadius(10)
          .onChange((v: string) => {
            this.hostInput = v;
          })
      }
      .width('100%')

      Row() {
        Text('端口')
          .fontSize(13)
          .fontColor(Theme.SUB)
          .width(56)
        TextInput({ placeholder: '如 8000', text: this.portInput })
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .backgroundColor(Theme.INPUT)
          .borderRadius(10)
          .type(InputType.Number)
          .onChange((v: string) => {
            this.portInput = v;
          })
      }
      .width('100%')

      Row() {
        Text('设备号')
          .fontSize(13)
          .fontColor(Theme.SUB)
          .width(56)
        TextInput({ placeholder: '如 0', text: this.deviceInput })
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .backgroundColor(Theme.INPUT)
          .borderRadius(10)
          .type(InputType.Number)
          .onChange((v: string) => {
            this.deviceInput = v;
          })
      }
      .width('100%')

      Row({ space: 10 }) {
        Button('保存并重连')
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .backgroundColor(Theme.PRIMARY)
          .borderRadius(10)
          .onClick(() => {
            this.saveConfig();
          })
        Button('立即刷新')
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .backgroundColor(Theme.PRIMARY_SOFT)
          .fontColor(Theme.PRIMARY)
          .borderRadius(10)
          .onClick(() => {
            HttpService.get().refresh();
            this.toast('已发起刷新');
          })
      }
      .width('100%')

      Text(ConfigStore.apiUrl(Constants.HTTP_HISTORY_LIMIT))
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
  statusBanner() {
    Column({ space: 4 }) {
      Row() {
        Column()
          .width(7)
          .height(7)
          .borderRadius(4)
          .backgroundColor(this.fetchOk ? Theme.OK : Theme.DANGER)
        Text(this.fetchMsg)
          .fontSize(12)
          .fontColor(this.fetchOk ? Theme.OK : Theme.DANGER)
          .margin({ left: 6 })
          .layoutWeight(1)
        Text(this.showSettings ? '收起设置' : '服务器设置')
          .fontSize(12)
          .fontColor(Theme.PRIMARY)
          .onClick(() => {
            this.showSettings = !this.showSettings;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        Text(this.lastUpdate > 0 ? `最后更新 ${DateUtil.time(this.lastUpdate)}` : '等待首次数据...')
          .fontSize(11)
          .fontColor(Theme.SUB)
          .layoutWeight(1)
        Text(this.showDebug ? '收起调试' : '接口调试')
          .fontSize(11)
          .fontColor(Theme.SUB)
          .onClick(() => {
            this.showDebug = !this.showDebug;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 9, bottom: 9 })
    .backgroundColor(Theme.GLASS)
    .borderRadius(12)
    .border({ width: 1, color: Theme.HAIRLINE })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  debugPanel() {
    Column({ space: 6 }) {
      Text('接口调试')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TEXT)
        .width('100%')
      Text(`请求地址：${ConfigStore.apiUrl(Constants.HTTP_HISTORY_LIMIT)}`)
        .fontSize(11)
        .fontColor(Theme.SUB)
        .width('100%')
      Text(`刷新次数：${this.revision}`)
        .fontSize(11)
        .fontColor(Theme.SUB)
        .width('100%')
      Text(`解析结果：门 ${this.current.door} / 存在 ${this.current.radarPresence} / 运动 ${this.current.radarMotion}`)
        .fontSize(11)
        .fontColor(Theme.TEXT)
        .width('100%')
      Text(`SOS ${this.current.sos} / 报警 ${this.current.alarm} / 上报时间 ${this.current.serverTs > 0 ? DateUtil.dateTime(this.current.serverTs) : '未知'}`)
        .fontSize(11)
        .fontColor(Theme.TEXT)
        .width('100%')
      Text('最近响应原文：')
        .fontSize(11)
        .fontColor(Theme.SUB)
        .width('100%')
        .margin({ top: 4 })
      Scroll() {
        Text(this.lastRaw.length > 0 ? this.lastRaw : '暂无响应')
          .fontSize(10)
          .fontColor(Theme.TEXT)
          .width('100%')
          .copyOption(CopyOptions.LocalDevice)
      }
      .width('100%')
      .height(150)
      .backgroundColor(Theme.CHIP)
      .borderRadius(8)
      .padding(6)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Theme.CARD)
    .borderRadius(16)
    .border({ width: 1, color: Theme.HAIRLINE })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  historyItem(rec: LatestRecord) {
    Row() {
      Column() {
        Text(DateUtil.time(rec.ts))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT)
        Text(rec.ts > 0 ? DateUtil.date(rec.ts) : '时间未知')
          .fontSize(11)
          .fontColor(Theme.SUB)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Row({ space: 10 }) {
        Text(`${rec.temp.toFixed(1)}℃`)
          .fontSize(13)
          .fontColor(Theme.PRIMARY)
        Text(`${rec.humi.toFixed(0)}%`)
          .fontSize(13)
          .fontColor(Theme.PRIMARY)
        Text(rec.door === 1 ? '门开' : '门关')
          .fontSize(12)
          .fontColor(rec.door === 1 ? Theme.WARN : Theme.SUB)
        Text(rec.radarPresence === 1 ? '有人' : '无人')
          .fontSize(12)
          .fontColor(rec.radarPresence === 1 ? Theme.OK : Theme.SUB)
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        // 顶部状态
        Row() {
          Column() {
            Text('居家守护')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.TEXT)
            Text(`设备号 ${this.current.deviceNo} · ${this.statusText()}`)
              .fontSize(12)
              .fontColor(Theme.SUB)
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Row() {
            Column()
              .width(8)
              .height(8)
              .borderRadius(4)
              .backgroundColor(this.current.online ? Theme.OK : Theme.SUB)
            Text(this.statusText())
              .fontSize(13)
              .fontColor(this.current.online ? Theme.OK : Theme.SUB)
              .margin({ left: 4 })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        this.statusBanner()

        if (this.showSettings) {
          this.settingsPanel()
        }

        if (this.showDebug) {
          this.debugPanel()
        }

        // 数据卡片
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          Column() {
            InfoCard({
              title: '室内温度',
              value: this.current.temp.toFixed(1),
              unit: '℃',
              icon: 'temp',
              accent: this.tempAccent()
            })
          }.width('48%').margin({ bottom: 12 })

          Column() {
            InfoCard({
              title: '室内湿度',
              value: this.current.humi.toFixed(0),
              unit: '%',
              icon: 'humidity',
              accent: Theme.PRIMARY
            })
          }.width('48%').margin({ bottom: 12 })

          Column() {
            InfoCard({
              title: '门窗状态',
              value: this.current.door === 1 ? '开启' : '关闭',
              icon: 'door',
              subtitle: this.current.door === 1 ? '请留意门窗是否关好' : '门窗处于关闭状态',
              accent: this.current.door === 1 ? Theme.WARN : Theme.OK
            })
          }.width('48%').margin({ bottom: 12 })

          Column() {
            InfoCard({
              title: '雷达存在',
              value: this.current.radarPresence === 1 ? '有人' : '无人',
              icon: 'presence',
              subtitle: '人体存在检测',
              accent: this.current.radarPresence === 1 ? Theme.OK : Theme.SUB
            })
          }.width('48%').margin({ bottom: 12 })

          Column() {
            InfoCard({
              title: '雷达运动',
              value: this.current.radarMotion === 1 ? '运动中' : '静止',
              icon: 'motion',
              subtitle: this.current.lastActive > 0 ? `最后活动 ${DateUtil.relative(this.current.lastActive)}` : '暂无活动',
              accent: this.current.radarMotion === 1 ? Theme.PRIMARY : Theme.SUB
            })
          }.width('48%').margin({ bottom: 12 })

          Column() {
            InfoCard({
              title: '紧急求助',
              value: this.current.sos === 1 ? '求助中' : '正常',
              icon: 'sos',
              subtitle: this.current.sos === 1 ? '老人已按下SOS按钮！' : '未触发',
              accent: this.current.sos === 1 ? Theme.DANGER : Theme.OK
            })
          }.width('48%').margin({ bottom: 12 })

          Column() {
            InfoCard({
              title: '报警状态',
              value: this.current.alarm === 1 ? (this.current.alarmType.length > 0 ? this.current.alarmType : '报警中') : '正常',
              icon: 'warning',
              subtitle: this.current.alarm === 1 ? '设备已触发报警' : '无报警',
              accent: this.current.alarm === 1 ? Theme.DANGER : Theme.OK
            })
          }.width('48%').margin({ bottom: 12 })

          Column() {
            InfoCard({
              title: '设备状态',
              value: this.statusText(),
              icon: 'signal',
              subtitle: this.current.serverTs > 0
                ? `最近上报 ${DateUtil.time(this.current.serverTs)}`
                : (this.lastUpdate > 0 ? `最后拉取 ${DateUtil.time(this.lastUpdate)}` : '等待数据...'),
              accent: this.current.online ? Theme.OK : Theme.DANGER
            })
          }.width('48%').margin({ bottom: 12 })
        }
        .width('100%')

        // SOS 醒目提示
        if (this.current.sos === 1) {
          Row() {
            Stack() {
              AppIcon({ name: 'sos', size: 19, color: '#FFFFFF', weight: 1.9 })
            }
            .width(34)
            .height(34)
            .borderRadius(11)
            .backgroundColor(Theme.alpha('#FFFFFF', 0.16))

            Text('检测到紧急求助信号，请立即处理！')
              .fontSize(15)
              .fontColor('#FFFFFF')
              .fontWeight(FontWeight.Bold)
              .margin({ left: 10 })
              .layoutWeight(1)
          }
          .width('100%')
          .padding(15)
          .backgroundColor(Theme.DANGER)
          .borderRadius(16)
          .shadow({ radius: 16, color: Theme.alpha(Theme.DANGER, 0.24), offsetX: 0, offsetY: 6 })
          .alignItems(VerticalAlign.Center)
        }

        // 报警醒目提示
        if (this.current.alarm === 1) {
          Row() {
            Stack() {
              AppIcon({ name: 'warning', size: 19, color: '#FFFFFF', weight: 1.9 })
            }
            .width(34)
            .height(34)
            .borderRadius(11)
            .backgroundColor(Theme.alpha('#FFFFFF', 0.16))

            Text(this.current.alarmType.length > 0
              ? `设备报警：${this.current.alarmType}`
              : '设备报警，请立即处理！')
              .fontSize(15)
              .fontColor('#FFFFFF')
              .fontWeight(FontWeight.Bold)
              .margin({ left: 10 })
              .layoutWeight(1)
          }
          .width('100%')
          .padding(15)
          .backgroundColor(Theme.DANGER)
          .borderRadius(16)
          .shadow({ radius: 16, color: Theme.alpha(Theme.DANGER, 0.24), offsetX: 0, offsetY: 6 })
          .alignItems(VerticalAlign.Center)
        }

        // 最近上报历史
        Column() {
          Row() {
            Text('最近上报记录')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT)
              .layoutWeight(1)
            Text(`最近 ${this.history.length} 条`)
              .fontSize(12)
              .fontColor(Theme.SUB)
          }
          .width('100%')

          if (this.history.length === 0) {
            Text('暂无历史记录')
              .fontSize(13)
              .fontColor(Theme.SUB)
              .width('100%')
              .margin({ top: 10 })
          } else {
            ForEach(this.history, (rec: LatestRecord) => {
              this.historyItem(rec)
            }, (rec: LatestRecord, index: number) => `${rec.id}-${index}`)
          }
        }
        .width('100%')
        .padding(14)
        .backgroundColor(Theme.CARD)
        .borderRadius(16)
        .border({ width: 1, color: Theme.HAIRLINE })
        .shadow({ radius: 14, color: Theme.SHADOW, offsetX: 0, offsetY: 4 })
        .alignItems(HorizontalAlign.Start)
      }
      .padding(16)
      .width('100%')
    }
    .backgroundColor(Theme.BG)
    .width('100%')
    .height('100%')
  }
}
