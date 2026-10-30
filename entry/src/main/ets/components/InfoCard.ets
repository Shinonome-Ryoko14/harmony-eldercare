import { Theme } from '../common/Theme';
import { AppIcon } from './AppIcon';

/** 通用信息卡片：毛玻璃底 + 发丝描边 + 单色图标 */
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
          Stack() {
            AppIcon({ name: this.icon, iconSize: 18, color: this.accent, weight: 1.8 })
          }
          .width(32)
          .height(32)
          .borderRadius(10)
          .backgroundColor(Theme.alpha(this.accent, 0.10))
          .margin({ right: 9 })
        }
        Text(this.title)
          .fontSize(13)
          .fontColor(Theme.SUB)
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        Text(this.value)
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.accent)
        if (this.unit.length > 0) {
          Text(this.unit)
            .fontSize(13)
            .fontColor(Theme.SUB)
            .margin({ left: 3, bottom: 4 })
        }
      }
      .alignItems(VerticalAlign.Bottom)
      .width('100%')
      .margin({ top: 10 })

      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .fontSize(11)
          .fontColor(Theme.SUB)
          .width('100%')
          .margin({ top: 5 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .padding(14)
    .backgroundColor(Theme.CARD)
    .borderRadius(16)
    .border({ width: 1, color: Theme.HAIRLINE })
    .shadow({ radius: 10, color: Theme.SHADOW, offsetX: 0, offsetY: 3 })
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
