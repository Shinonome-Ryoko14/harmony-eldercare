import { SafetyLog } from '../common/Types';
import { DateUtil } from '../common/Protocol';
import { Theme } from '../common/Theme';
import { AppStore } from '../store/AppStore';
import { ConfigStore } from '../store/ConfigStore';
import { Repository } from '../data/Repository';
import { ConnectionBadge } from '../components/ConnectionBadge';

@Component
export struct LogPage {
  @State logs: SafetyLog[] = [];
  @State fetchOk: boolean = false;
  @State fetchMsg: string = '未连接';
  private timer: number = -1;

  aboutToAppear(): void {
    this.reload();
    this.timer = setInterval(() => {
      this.reload();
    }, 4000);
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
      this.logs = await Repository.queryLogs(200);
    } catch (e) {
      console.error(`加载日志失败: ${JSON.stringify(e)}`);
    }
  }

  @Builder
  logItem(log: SafetyLog) {
    Column() {
      Row() {
        Text(log.alertType)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT)
          .layoutWeight(1)
        Text(DateUtil.date(log.ts))
          .fontSize(12)
          .fontColor(Theme.SUB)
      }
      .width('100%')

      Text(log.result)
        .fontSize(13)
        .fontColor(Theme.TEXT)
        .width('100%')
        .margin({ top: 8 })

      Row() {
        Text(`处置人：${log.operator}`)
          .fontSize(12)
          .fontColor(Theme.SUB)
          .layoutWeight(1)
        Text(DateUtil.time(log.ts))
          .fontSize(12)
          .fontColor(Theme.SUB)
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding(15)
    .backgroundColor(Theme.CARD)
    .borderRadius(16)
    .border({ width: 1, color: Theme.HAIRLINE })
    .shadow({ radius: 14, color: Theme.SHADOW, offsetX: 0, offsetY: 4 })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Text('居家安全日志')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT)
          .width('100%')
        Text('记录每一次告警处置结果，用于历史追溯')
          .fontSize(12)
          .fontColor(Theme.SUB)
          .width('100%')

        ConnectionBadge({
          ok: this.fetchOk,
          message: this.fetchMsg,
          serverUrl: ConfigStore.baseUrl()
        })

        if (this.logs.length === 0) {
          Text('暂无处置记录')
            .fontSize(14)
            .fontColor(Theme.SUB)
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 60 })
        } else {
          ForEach(this.logs, (log: SafetyLog) => {
            this.logItem(log)
          }, (log: SafetyLog) => `${log.id}`)
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
