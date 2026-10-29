import { AlertRecord } from '../common/Types';
import { DateUtil } from '../common/Protocol';
import { Theme } from '../common/Theme';
import { AppStore } from '../store/AppStore';
import { ConfigStore } from '../store/ConfigStore';
import { AiBus } from '../store/AiBus';
import { Repository } from '../data/Repository';
import { ConnectionBadge } from '../components/ConnectionBadge';
import { AppIcon } from '../components/AppIcon';

const EMPTY_ALERT: AlertRecord = {
  id: 0,
  deviceNo: -1,
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
  @State fetchOk: boolean = false;
  @State fetchMsg: string = '未连接';
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
      this.fetchOk = AppStore.get().getFetchState().ok;
      this.fetchMsg = AppStore.get().getFetchState().message;
      let deviceNo: number = AppStore.get().getSelectedDeviceNo();
      let list: AlertRecord[] = await Repository.queryAlerts(deviceNo, 100);
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

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (err) {
      console.error(`提示弹出失败: ${JSON.stringify(err)}`);
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

  /** 把告警上下文交给 AI 页解读，并由底部导航自动切换过去 */
  private askAi(a: AlertRecord): void {
    let prompt: string = `请解读这条居家安全告警，并给出可执行的处置建议。\n` +
      `类型：${a.type}\n` +
      `时间：${DateUtil.dateTime(a.ts)}\n` +
      `详情：${a.message}\n` +
      `当前状态：${a.handled === 1 ? `已处置（${a.handleResult}）` : '未处置'}\n` +
      `请按“风险判断 / 建议步骤 / 是否需要联系家属”三部分回答。`;
    AiBus.get().ask(prompt, a);
  }

  private async submitHandle(): Promise<void> {
    let result: string = this.resultText.trim();
    if (result.length === 0) {
      this.toast('请填写或选择处置结果');
      return;
    }
    let operator: string = this.operatorText.trim();
    if (operator.length === 0) {
      operator = '监护人';
    }
    try {
      await Repository.handleAlert(this.activeAlert, result, operator);
      this.showDialog = false;
      this.toast('处置结果已保存');
      await this.reload();
    } catch (e) {
      console.error(`保存处置失败: ${JSON.stringify(e)}`);
      this.toast('保存失败，请重试');
    }
  }

  @Builder
  alertItem(a: AlertRecord) {
    Column() {
      Row() {
        Row() {
          Column()
            .width(7)
            .height(7)
            .borderRadius(4)
            .backgroundColor(this.levelColor(a.level))
          Text(a.type)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TEXT)
            .margin({ left: 6 })
        }
        .layoutWeight(1)

        Text(a.handled === 1 ? '已处置' : '待处置')
          .fontSize(11)
          .fontColor(a.handled === 1 ? Theme.OK : Theme.DANGER)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor(a.handled === 1 ? Theme.OK_SOFT : Theme.DANGER_SOFT)
          .borderRadius(8)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

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
        .backgroundColor(Theme.OK_SOFT)
        .borderRadius(9)

        Row() {
          AppIcon({ name: 'ai', size: 13, color: Theme.PRIMARY })
          Text('让 AI 复盘这条告警')
            .fontSize(12)
            .fontColor(Theme.PRIMARY)
            .margin({ left: 5 })
        }
        .margin({ top: 9 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.askAi(a);
        })
      } else {
        Row({ space: 8 }) {
          Button('AI 解读')
            .height(34)
            .fontSize(13)
            .backgroundColor(Theme.PRIMARY_SOFT)
            .fontColor(Theme.PRIMARY)
            .borderRadius(9)
            .onClick(() => {
              this.askAi(a);
            })
          Button('填写处置结果')
            .height(34)
            .fontSize(13)
            .backgroundColor(Theme.PRIMARY)
            .borderRadius(9)
            .onClick(() => {
              this.openHandle(a);
            })
        }
        .width('100%')
        .margin({ top: 10 })
      }
    }
    .width('100%')
    .padding(15)
    .backgroundColor(Theme.CARD)
    .borderRadius(16)
    .border({ width: 1, color: Theme.HAIRLINE })
    .shadow({ radius: 14, color: Theme.SHADOW, offsetX: 0, offsetY: 4 })
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
            .backgroundColor(this.resultText === r ? Theme.PRIMARY : Theme.PRIMARY_SOFT)
            .padding({ left: 10, right: 10, top: 7, bottom: 7 })
            .borderRadius(9)
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
        .backgroundColor(Theme.INPUT)
        .borderRadius(10)
        .onChange((v: string) => {
          this.resultText = v;
        })

      TextInput({ placeholder: '处置人（选填，默认：监护人）', text: this.operatorText })
        .width('100%')
        .height(40)
        .fontSize(14)
        .margin({ top: 10 })
        .backgroundColor(Theme.INPUT)
        .borderRadius(10)
        .onChange((v: string) => {
          this.operatorText = v;
        })

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(42)
          .backgroundColor(Theme.CHIP)
          .fontColor(Theme.TEXT)
          .borderRadius(11)
          .onClick(() => {
            this.showDialog = false;
          })
        Button('保存')
          .layoutWeight(1)
          .height(42)
          .backgroundColor(Theme.PRIMARY)
          .borderRadius(11)
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
    .borderRadius(22)
    .border({ width: 1, color: Theme.HAIRLINE })
    .shadow({ radius: 28, color: Theme.SHADOW_STRONG, offsetX: 0, offsetY: 12 })
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
                .fontSize(11)
                .fontColor(Theme.DANGER)
                .backgroundColor(Theme.DANGER_SOFT)
                .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                .borderRadius(8)
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          ConnectionBadge({
            ok: this.fetchOk,
            message: this.fetchMsg,
            serverUrl: ConfigStore.baseUrl()
          })

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
        .backgroundColor('rgba(16, 32, 34, 0.32)')
        .backdropBlur(8)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
  }
}
