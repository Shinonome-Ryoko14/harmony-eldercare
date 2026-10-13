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
        Column()
          .width(8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(this.ok ? Theme.OK : Theme.DANGER)
        Text(this.message)
          .fontSize(12)
          .fontColor(this.ok ? Theme.OK : Theme.DANGER)
          .margin({ left: 6 })
          .layoutWeight(1)
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
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor(Theme.CARD)
    .borderRadius(12)
    .alignItems(HorizontalAlign.Start)
  }
}
