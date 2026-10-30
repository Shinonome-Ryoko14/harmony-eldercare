import { DayStat } from '../common/Types';
import { Theme } from '../common/Theme';
import { AppStore } from '../store/AppStore';
import { ConfigStore } from '../store/ConfigStore';
import { Repository } from '../data/Repository';
import { BarChart } from '../components/BarChart';
import { ConnectionBadge } from '../components/ConnectionBadge';
import { AppIcon } from '../components/AppIcon';

@Component
export struct StatsPage {
  @State week: DayStat[] = [];
  @State month: DayStat[] = [];
  @State showMonth: boolean = false;
  @State risk: string = '';
  @State fetchOk: boolean = false;
  @State fetchMsg: string = '未连接';
  private timer: number = -1;

  aboutToAppear(): void {
    this.reload();
    this.timer = setInterval(() => {
      this.reload();
    }, 5000);
  }

  aboutToDisappear(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private async reload(): Promise<void> {
    try {
      this.fetchOk = AppStore.get().getFetchState().ok;
      this.fetchMsg = AppStore.get().getFetchState().message;
      let deviceNo: number = AppStore.get().getSelectedDeviceNo();
      this.week = await Repository.dailyTrend(deviceNo, 7);
      this.month = await Repository.dailyTrend(deviceNo, 30);
      this.risk = this.evaluateRisk();
    } catch (e) {
      console.error(`加载统计失败: ${JSON.stringify(e)}`);
    }
  }

  private sum(list: DayStat[], from: number, to: number): number {
    let s: number = 0;
    for (let i: number = from; i <= to && i < list.length; i++) {
      s += list[i].count;
    }
    return s;
  }

  private evaluateRisk(): string {
    if (this.week.length < 7) {
      return '';
    }
    let recent3: number = this.sum(this.week, 4, 6);
    let prev3: number = this.sum(this.week, 1, 3);
    if (prev3 >= 3 && recent3 < prev3 * 0.6) {
      return '近期活动量明显下降，可能存在健康或情绪风险，建议尽快联系或上门探望。';
    }
    if (prev3 >= 3 && recent3 < prev3 * 0.85) {
      return '近期活动量略有下降，请留意老人日常状态。';
    }
    return '';
  }

  @Builder
  totalRow(title: string, value: string) {
    Row() {
      Text(title)
        .fontSize(14)
        .fontColor(Theme.SUB)
        .layoutWeight(1)
      Text(value)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.PRIMARY)
    }
    .width('100%')
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Text('数据统计分析')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT)
          .width('100%')

        ConnectionBadge({
          ok: this.fetchOk,
          message: this.fetchMsg,
          serverUrl: ConfigStore.baseUrl()
        })

        Row() {
          Row({ space: 2 }) {
            Text('本周趋势')
              .fontSize(13)
              .fontColor(this.showMonth ? Theme.SUB : Theme.TEXT)
              .fontWeight(this.showMonth ? FontWeight.Normal : FontWeight.Medium)
              .backgroundColor(this.showMonth ? Color.Transparent : Theme.CARD_SOLID)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .borderRadius(9)
              .shadow({
                radius: this.showMonth ? 0 : 6,
                color: Theme.SHADOW,
                offsetX: 0,
                offsetY: 2
              })
              .onClick(() => {
                this.showMonth = false;
              })
            Text('近30天趋势')
              .fontSize(13)
              .fontColor(this.showMonth ? Theme.TEXT : Theme.SUB)
              .fontWeight(this.showMonth ? FontWeight.Medium : FontWeight.Normal)
              .backgroundColor(this.showMonth ? Theme.CARD_SOLID : Color.Transparent)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .borderRadius(9)
              .shadow({
                radius: this.showMonth ? 6 : 0,
                color: Theme.SHADOW,
                offsetX: 0,
                offsetY: 2
              })
              .onClick(() => {
                this.showMonth = true;
              })
          }
          .padding(4)
          .backgroundColor(Theme.CHIP)
          .borderRadius(12)

          Blank()
        }
        .width('100%')

        Column() {
          Text(this.showMonth ? '近30天每日活动量' : '近7天每日活动量')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TEXT)
            .width('100%')
            .margin({ bottom: 10 })
          BarChart({
            values: (this.showMonth ? this.month : this.week).map((d: DayStat) => d.count),
            labels: (this.showMonth ? this.month : this.week).map((d: DayStat) => d.label),
            barColor: Theme.PRIMARY,
            chartHeight: 140,
            showLabels: !this.showMonth
          })
        }
        .padding(16)
        .backgroundColor(Theme.CARD)
        .borderRadius(16)
        .border({ width: 1, color: Theme.HAIRLINE })
        .shadow({ radius: 14, color: Theme.SHADOW, offsetX: 0, offsetY: 4 })
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Column({ space: 10 }) {
          this.totalRow('本周活动总量', `${this.sum(this.week, 0, 6)} 次`)
          Divider().color(Theme.BORDER)
          this.totalRow('本周日均活动', `${(this.sum(this.week, 0, 6) / 7).toFixed(1)} 次`)
          Divider().color(Theme.BORDER)
          this.totalRow('近30天活动总量', `${this.sum(this.month, 0, 29)} 次`)
        }
        .padding(16)
        .backgroundColor(Theme.CARD)
        .borderRadius(16)
        .border({ width: 1, color: Theme.HAIRLINE })
        .shadow({ radius: 14, color: Theme.SHADOW, offsetX: 0, offsetY: 4 })
        .width('100%')

        if (this.risk.length > 0) {
          Row() {
            Stack() {
              AppIcon({ name: 'warning', iconSize: 18, color: Theme.WARN, weight: 1.8 })
            }
            .width(32)
            .height(32)
            .borderRadius(9)
            .backgroundColor(Theme.CARD)
            Column() {
              Text('活动量下降风险提示')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.WARN)
              Text(this.risk)
                .fontSize(13)
                .fontColor(Theme.WARN)
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .margin({ left: 9 })
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding(14)
          .backgroundColor(Theme.WARN_SOFT)
          .borderRadius(14)
          .border({ width: 1, color: Theme.alpha(Theme.WARN, 0.14) })
          .alignItems(VerticalAlign.Top)
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
