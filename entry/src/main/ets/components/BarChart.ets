import { Theme } from '../common/Theme';

/** 基于布局的柱状图：浅色轨道 + 纯色柱体，随数据自动刷新 */
@Component
export struct BarChart {
  @Prop values: number[] = [];
  @Prop labels: string[] = [];
  @Prop barColor: string = Theme.PRIMARY;
  @Prop chartHeight: number = 140;
  @Prop showLabels: boolean = true;

  private maxValue(): number {
    let m: number = 1;
    this.values.forEach((v: number) => {
      if (v > m) {
        m = v;
      }
    });
    return m;
  }

  private labelAt(i: number): string {
    return i < this.labels.length ? this.labels[i] : '';
  }

  build() {
    Scroll() {
      Row() {
        ForEach(this.values, (v: number, i: number) => {
          Column() {
            Column() {
              Column()
                .width(14)
                .height(Math.max(4, v / this.maxValue() * this.chartHeight))
                .backgroundColor(this.barColor)
                .borderRadius(7)
            }
            .width(16)
            .height(this.chartHeight)
            .justifyContent(FlexAlign.End)
            .backgroundColor(Theme.CHIP)
            .borderRadius(8)

            if (this.showLabels) {
              Text(this.labelAt(i))
                .fontSize(9)
                .fontColor(Theme.SUB)
                .margin({ top: 5 })
            }
          }
          .margin({ left: 5, right: 5 })
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.End)
        }, (v: number, i: number) => `${i}-${v}`)
      }
      .alignItems(VerticalAlign.Bottom)
      .height(this.chartHeight + 24)
    }
    .scrollable(ScrollDirection.Horizontal)
    .width('100%')
    .height(this.chartHeight + 30)
    .scrollBar(BarState.Off)
  }
}
