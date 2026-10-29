import { Theme } from '../common/Theme';

/** 顶部连接状态条：各页面共用的服务器连接指示 */
@Component
export struct ConnectionBadge {
  @Prop ok: boolean = false;
  @Prop message: string = '未连接';
  @Prop serverUrl: string = '';

  build() {
    Column() {
      Row() {
        Row() {
          Column()
            .width(7)
            .height(7)
            .borderRadius(4)
            .backgroundColor(this.ok ? Theme.OK : Theme.DANGER)
          Text(this.message)
            .fontSize(12)
            .fontColor(this.ok ? Theme.OK : Theme.DANGER)
            .margin({ left: 6 })
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)

        Text('HTTP')
          .fontSize(9)
          .fontColor(Theme.SUB)
          .letterSpacing(0.6)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor(Theme.CHIP)
          .borderRadius(5)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.serverUrl.length > 0) {
        Text(this.serverUrl)
          .fontSize(10)
          .fontColor(Theme.SUB)
          .width('100%')
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 9, bottom: 9 })
    .backgroundColor(Theme.GLASS)
    .borderRadius(12)
    .border({ width: 1, color: Theme.HAIRLINE })
    .alignItems(HorizontalAlign.Start)
  }
}
