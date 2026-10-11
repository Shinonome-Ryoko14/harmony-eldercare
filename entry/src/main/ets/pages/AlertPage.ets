import { promptAction } from '@kit.ArkUI';
import { AlertRecord } from '../common/Types';
import { DateUtil } from '../common/Protocol';
import { Theme } from '../common/Theme';
import { AppStore } from '../store/AppStore';
import { Repository } from '../data/Repository';

const EMPTY_ALERT: AlertRecord = {
  id: 0,
  ip: '',
  ts: 0,
  type: '',
  level: 0,
  message: '',
  handled: 0,
  handleResult: '',
  handleTs: 0
};

const QUICK_RESULTS: string[] = [
  '误报，老人状态正常',
  '已电话联系老人确认安全',
  '已联系社区网格员上门查看',
  '老人身体不适，已拨打120',
  '已通知家属'
];

@Component
export struct AlertPage {
  @State alerts: AlertRecord[] = [];
  @State pendingCount: number = 0;
  @State showDialog: boolean = false;
  @State activeAlert: AlertRecord = EMPTY_ALERT;
  @State resultText: string = '';
  @State operatorText: string = '';
  private timer: number = -1;

  aboutToAppear(): void {
    this.reload();
    this.timer = setInterval(() => {
      this.reload();
    }, 3000);
  }

  aboutToDisappear(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private async reload(): Promise<void> {
    try {
      let ip: string = AppStore.get().getSelectedIp();
      let list: AlertRecord[] = await Repository.queryAlerts(ip, 100);
      let pending: number = 0;
      list.forEach((a: AlertRecord) => {
        if (a.handled === 0) {
          pending = pending + 1;
        }
      });
      this.alerts = list;
      this.pendingCount = pending;
    } catch (e) {
      console.error(`加载告警失败: ${JSON.stringify(e)}`);
    }
  }

  private levelColor(level: number): string {
    if (level >= 2) {
      return Theme.DANGER;
    }
    if (level === 1) {
      return Theme.WARN;
    }
    return Theme.PRIMARY;
  }

  private openHandle(a: AlertRecord): void {
    this.activeAlert = a;
    this.resultText = '';
    this.operatorText = '';
    this.showDialog = true;
  }

  private async submitHandle(): Promise<void> {
    let result: string = this.resultText.trim();
    if (result.length === 0) {
      promptAction.showToast({ message: '请填写或选择处置结果' });
      return;
    }
    let operator: string = this.operatorText.trim();
    if (operator.length === 0) {
      operator = '监护人';
    }
    try {
      await Repository.handleAlert(this.activeAlert, result, operator);
      this.showDialog = false;
      promptAction.showToast({ message: '处置结果已保存' });
      await this.reload();
    } catch (e) {
      console.error(`保存处置失败: ${JSON.stringify(e)}`);
      promptAction.showToast({ message: '保存失败，请重试' });
    }
  }

  @Builder
  alertItem(a: AlertRecord) {
    Column() {
      Row() {
        Row() {
          Circle({ width: 8, height: 8 })
            .fill(this.levelColor(a.level))
          Text(a.type)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TEXT)
            .margin({ left: 6 })
        }
        .layoutWeight(1)

        Text(a.handled === 1 ? '已处置' : '待处置')
          .fontSize(12)
          .fontColor(a.handled === 1 ? Theme.OK : Theme.DANGER)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .backgroundColor(a.handled === 1 ? '#E8F5E9' : '#FFEBEE')
          .borderRadius(10)
      }
      .width('100%')

      Text(a.message)
        .fontSize(13)
        .fontColor(Theme.SUB)
        .width('100%')
        .margin({ top: 6 })

      Text(DateUtil.dateTime(a.ts))
        .fontSize(12)
        .fontColor(Theme.SUB)
        .width('100%')
        .margin({ top: 6 })

      if (a.handled === 1) {
        Column() {
          Text(`处置结果：${a.handleResult}`)
            .fontSize(13)
            .fontColor(Theme.OK)
            .width('100%')
          Text(`处置时间：${DateUtil.dateTime(a.handleTs)}`)
            .fontSize(12)
            .fontColor(Theme.SUB)
            .width('100%')
            .margin({ top: 2 })
        }
        .width('100%')
        .padding(10)
        .margin({ top: 8 })
        .backgroundColor('#F6FBF6')
        .borderRadius(8)
      } else {
        Button('填写处置结果')
          .height(34)
          .fontSize(14)
          .backgroundColor(Theme.PRIMARY)
          .margin({ top: 10 })
          .onClick(() => {
            this.openHandle(a);
          })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Theme.CARD)
    .borderRadius(14)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  handleDialog() {
    Column() {
      Text('事件闭环处置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TEXT)
        .width('100%')
      Text(this.activeAlert.type)
        .fontSize(13)
        .fontColor(Theme.DANGER)
        .width('100%')
        .margin({ top: 6 })
      Text(this.activeAlert.message)
        .fontSize(13)
        .fontColor(Theme.SUB)
        .width('100%')
        .margin({ top: 4 })

      Text('快捷选择')
        .fontSize(13)
        .fontColor(Theme.SUB)
        .width('100%')
        .margin({ top: 12 })
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(QUICK_RESULTS, (r: string) => {
          Text(r)
            .fontSize(12)
            .fontColor(this.resultText === r ? '#FFFFFF' : Theme.PRIMARY)
            .backgroundColor(this.resultText === r ? Theme.PRIMARY : '#E0F2F1')
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(14)
            .margin({ right: 8, top: 8 })
            .onClick(() => {
              this.resultText = r;
            })
        }, (r: string) => r)
      }
      .width('100%')

      TextArea({ placeholder: '填写详细处置结果', text: this.resultText })
        .width('100%')
        .height(80)
        .fontSize(14)
        .margin({ top: 12 })
        .onChange((v: string) => {
          this.resultText = v;
        })

      TextInput({ placeholder: '处置人（选填，默认：监护人）', text: this.operatorText })
        .width('100%')
        .height(40)
        .fontSize(14)
        .margin({ top: 10 })
        .onChange((v: string) => {
          this.operatorText = v;
        })

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(42)
          .backgroundColor('#EEEEEE')
          .fontColor(Theme.TEXT)
          .onClick(() => {
            this.showDialog = false;
          })
        Button('保存')
          .layoutWeight(1)
          .height(42)
          .backgroundColor(Theme.PRIMARY)
          .onClick(() => {
            this.submitHandle();
          })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('92%')
    .padding(20)
    .backgroundColor(Theme.CARD)
    .borderRadius(18)
  }

  build() {
    Stack() {
      Scroll() {
        Column({ space: 12 }) {
          Row() {
            Text('历史预警记录')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.TEXT)
              .layoutWeight(1)
            if (this.pendingCount > 0) {
              Text(`待处置 ${this.pendingCount}`)
                .fontSize(12)
                .fontColor('#FFFFFF')
                .backgroundColor(Theme.DANGER)
                .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .borderRadius(12)
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          if (this.alerts.length === 0) {
            Text('暂无告警记录，系统运行正常')
              .fontSize(14)
              .fontColor(Theme.SUB)
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ top: 60 })
          } else {
            ForEach(this.alerts, (a: AlertRecord) => {
              this.alertItem(a)
            }, (a: AlertRecord) => `${a.id}-${a.handled}`)
          }
        }
        .padding(16)
        .width('100%')
      }
      .backgroundColor(Theme.BG)
      .width('100%')
      .height('100%')

      if (this.showDialog) {
        Column() {
          this.handleDialog()
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.45)')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
  }
}
