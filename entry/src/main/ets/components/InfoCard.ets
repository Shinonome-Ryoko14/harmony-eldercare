import { Theme } from '../common/Theme';

/** 通用信息卡片 */
@Component
export struct InfoCard {
  @Prop title: string = '';
  @Prop value: string = '';
  @Prop unit: string = '';
  @Prop subtitle: string = '';
  @Prop accent: string = Theme.PRIMARY;
  @Prop icon: string = '';

  build() {
    Column() {
      Row() {
        if (this.icon.length > 0) {
          Text(this.icon)
            .fontSize(20)
            .margin({ right: 6 })
        }
        Text(this.title)
          .fontSize(14)
          .fontColor(Theme.SUB)
          .layoutWeight(1)
      }
      .width('100%')

      Row() {
        Text(this.value)
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.accent)
        if (this.unit.length > 0) {
          Text(this.unit)
            .fontSize(14)
            .fontColor(Theme.SUB)
            .margin({ left: 4, bottom: 4 })
        }
      }
      .alignItems(VerticalAlign.Bottom)
      .width('100%')
      .margin({ top: 8 })

      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .fontSize(12)
          .fontColor(Theme.SUB)
          .width('100%')
          .margin({ top: 6 })
      }
    }
    .padding(16)
    .backgroundColor(Theme.CARD)
    .borderRadius(14)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
