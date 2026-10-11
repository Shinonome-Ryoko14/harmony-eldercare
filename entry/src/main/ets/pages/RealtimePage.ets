import { promptAction } from '@kit.ArkUI';
import { DeviceData } from '../common/Types';
import { Constants } from '../common/Constants';
import { DateUtil } from '../common/Protocol';
import { Theme } from '../common/Theme';
import { AppStore, StoreListener } from '../store/AppStore';
import { UdpService } from '../network/UdpService';
import { InfoCard } from '../components/InfoCard';

const EMPTY_DEVICE: DeviceData = {
  ip: '',
  temp: 0,
  humi: 0,
  magnet: 0,
  pulse: 0,
  total: 0,
  sos: 0,
  lastSeen: 0,
  lastActive: 0,
  online: false
};

@Component
export struct RealtimePage {
  @State deviceIps: string[] = [];
  @State current: DeviceData = EMPTY_DEVICE;
  @State inputIp: string = '';
  @State tick: number = 0;
  private timer: number = -1;

  private listener: StoreListener = (devices: DeviceData[]) => {
    let ips: string[] = [];
    devices.forEach((d: DeviceData) => {
      ips.push(d.ip);
    });
    this.deviceIps = ips;
    let cur: DeviceData | undefined = AppStore.get().current();
    if (cur !== undefined) {
      this.current = cur;
    }
  };

  aboutToAppear(): void {
    AppStore.get().subscribe(this.listener);
    this.listener(AppStore.get().getDevices());
    this.timer = setInterval(() => {
      this.tick = this.tick + 1;
    }, 1000);
  }

  aboutToDisappear(): void {
    AppStore.get().unsubscribe(this.listener);
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
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

  @Builder
  deviceChip(ip: string) {
    Text(ip)
      .fontSize(13)
      .fontColor(AppStore.get().getSelectedIp() === ip ? '#FFFFFF' : Theme.PRIMARY)
      .backgroundColor(AppStore.get().getSelectedIp() === ip ? Theme.PRIMARY : '#E0F2F1')
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(16)
      .margin({ right: 8 })
      .onClick(() => {
        AppStore.get().setSelectedIp(ip);
      })
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
            Text(`已发现 ${this.deviceIps.length} 台设备`)
              .fontSize(12)
              .fontColor(Theme.SUB)
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Row() {
            Circle({ width: 8, height: 8 })
              .fill(this.current.online ? Theme.OK : Theme.SUB)
            Text(this.statusText())
              .fontSize(13)
              .fontColor(this.current.online ? Theme.OK : Theme.SUB)
              .margin({ left: 4 })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        // 设备选择
        if (this.deviceIps.length > 0) {
          Scroll() {
            Row() {
              ForEach(this.deviceIps, (ip: string) => {
                this.deviceChip(ip)
              }, (ip: string) => ip)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .width('100%')
        }

        // 手动连接
        Row() {
          TextInput({ placeholder: '手动输入设备IP，如 192.168.1.100', text: this.inputIp })
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .onChange((v: string) => {
              this.inputIp = v;
            })
          Button('连接')
            .height(40)
            .fontSize(14)
            .backgroundColor(Theme.PRIMARY)
            .margin({ left: 8 })
            .onClick(() => {
              let ip: string = this.inputIp.trim();
              if (ip.length === 0) {
                promptAction.showToast({ message: '请输入设备IP' });
                return;
              }
              UdpService.get().probeIp(ip);
              promptAction.showToast({ message: `已向 ${ip} 发送探测包` });
            })
        }
        .width('100%')

        // 数据卡片
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          Column() {
            InfoCard({
              title: '室内温度',
              value: this.current.temp.toFixed(1),
              unit: '℃',
              icon: '🌡️',
              accent: this.tempAccent()
            })
          }.width('48%').margin({ bottom: 12 })

          Column() {
            InfoCard({
              title: '室内湿度',
              value: this.current.humi.toFixed(0),
              unit: '%',
              icon: '💧',
              accent: Theme.PRIMARY
            })
          }.width('48%').margin({ bottom: 12 })

          Column() {
            InfoCard({
              title: '门窗状态',
              value: this.current.magnet === 1 ? '开启' : '关闭',
              icon: '🚪',
              subtitle: this.current.magnet === 1 ? '请留意门窗是否关好' : '门窗处于关闭状态',
              accent: this.current.magnet === 1 ? Theme.WARN : Theme.OK
            })
          }.width('48%').margin({ bottom: 12 })

          Column() {
            InfoCard({
              title: '人体活动',
              value: this.current.lastActive > 0 ? DateUtil.relative(this.current.lastActive) : '暂无',
              icon: '🚶',
              subtitle: '最后活动时间',
              accent: Theme.PRIMARY
            })
          }.width('48%').margin({ bottom: 12 })

          Column() {
            InfoCard({
              title: '设备状态',
              value: this.statusText(),
              icon: '📶',
              subtitle: this.current.lastSeen > 0 ? `最近上报 ${DateUtil.time(this.current.lastSeen)}` : '等待数据...',
              accent: this.current.online ? Theme.OK : Theme.DANGER
            })
          }.width('48%').margin({ bottom: 12 })

          Column() {
            InfoCard({
              title: '紧急求助',
              value: this.current.sos === 1 ? '求助中' : '正常',
              icon: '🆘',
              subtitle: this.current.sos === 1 ? '老人已按下SOS按钮！' : '未触发',
              accent: this.current.sos === 1 ? Theme.DANGER : Theme.OK
            })
          }.width('48%').margin({ bottom: 12 })
        }
        .width('100%')

        // SOS 醒目提示
        if (this.current.sos === 1) {
          Row() {
            Text('🆘')
              .fontSize(24)
            Text('检测到紧急求助信号，请立即处理！')
              .fontSize(15)
              .fontColor('#FFFFFF')
              .fontWeight(FontWeight.Bold)
              .margin({ left: 8 })
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Theme.DANGER)
          .borderRadius(14)
        }
      }
      .padding(16)
      .width('100%')
    }
    .backgroundColor(Theme.BG)
    .width('100%')
    .height('100%')
  }
}
