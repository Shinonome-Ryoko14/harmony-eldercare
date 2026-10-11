import { HourStat, ReportData } from '../common/Types';
import { Theme } from '../common/Theme';
import { AppStore, StoreListener } from '../store/AppStore';
import { Repository } from '../data/Repository';
import { BarChart } from '../components/BarChart';

function defaultReport(): ReportData {
  let hourly: HourStat[] = [];
  for (let h: number = 0; h < 24; h++) {
    hourly.push({ hour: h, count: 0 });
  }
  return { today: 0, yesterday: 0, diff: 0, hourly: hourly };
}

@Component
export struct ReportPage {
  @State report: ReportData = defaultReport();
  @State currentIp: string = '';
  @State loaded: boolean = false;
  private timer: number = -1;
  private listener: StoreListener = () => {
    this.reload();
  };

  aboutToAppear(): void {
    AppStore.get().subscribe(this.listener);
    this.reload();
    this.timer = setInterval(() => {
      this.reload();
    }, 3000);
  }

  aboutToDisappear(): void {
    AppStore.get().unsubscribe(this.listener);
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private async reload(): Promise<void> {
    let ip: string = AppStore.get().getSelectedIp();
    this.currentIp = ip;
    try {
      let r: ReportData = await Repository.report(ip);
      this.report = r;
      this.loaded = true;
    } catch (e) {
      console.error(`加载报告失败: ${JSON.stringify(e)}`);
    }
  }

  private trendText(): string {
    if (this.report.diff > 0) {
      return `较昨日增加 ${this.report.diff} 次`;
    }
    if (this.report.diff < 0) {
      return `较昨日减少 ${-this.report.diff} 次`;
    }
    return '与昨日持平';
  }

  private trendColor(): string {
    if (this.report.diff > 0) {
      return Theme.OK;
    }
    if (this.report.diff < 0) {
      return Theme.WARN;
    }
    return Theme.SUB;
  }

  @Builder
  statBox(title: string, value: string, color: string) {
    Column() {
      Text(value)
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
      Text(title)
        .fontSize(12)
        .fontColor(Theme.SUB)
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .padding(16)
    .backgroundColor(Theme.CARD)
    .borderRadius(14)
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Text('老人活动规律报告')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT)
          .width('100%')
        Text(this.currentIp.length > 0 ? `设备 ${this.currentIp}` : '暂无设备，等待数据上报')
          .fontSize(12)
          .fontColor(Theme.SUB)
          .width('100%')

        Row({ space: 12 }) {
          this.statBox('今日活动频次', `${this.report.today}`, Theme.PRIMARY)
          this.statBox('昨日活动频次', `${this.report.yesterday}`, Theme.SUB)
        }
        .width('100%')

        Column() {
          Row() {
            Text('对比昨日')
              .fontSize(14)
              .fontColor(Theme.SUB)
              .layoutWeight(1)
            Text(this.trendText())
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.trendColor())
          }
          .width('100%')

          if (this.report.today === 0 && this.report.yesterday === 0) {
            Text('暂无活动数据，活动数据将随老人日常活动自动统计')
              .fontSize(12)
              .fontColor(Theme.SUB)
              .width('100%')
              .margin({ top: 8 })
          }
        }
        .padding(16)
        .backgroundColor(Theme.CARD)
        .borderRadius(14)
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Column() {
          Text('今日活动时段分布')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TEXT)
            .width('100%')
            .margin({ bottom: 8 })
          BarChart({
            values: this.report.hourly.map((h: HourStat) => h.count),
            labels: this.report.hourly.map((h: HourStat) => `${h.hour}`),
            barColor: Theme.PRIMARY,
            chartHeight: 120,
            showLabels: true
          })
        }
        .padding(16)
        .backgroundColor(Theme.CARD)
        .borderRadius(14)
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        if (this.report.today > 0 && this.report.today < this.report.yesterday) {
          Row() {
            Text('⚠️')
              .fontSize(18)
            Text('今日活动量低于昨日，请关注老人状态，必要时电话问候。')
              .fontSize(13)
              .fontColor(Theme.WARN)
              .margin({ left: 8 })
              .layoutWeight(1)
          }
          .width('100%')
          .padding(14)
          .backgroundColor('#FFF3E0')
          .borderRadius(12)
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
