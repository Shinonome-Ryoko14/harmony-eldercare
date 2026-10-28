import { Theme } from '../common/Theme';
import { ReportPage } from './ReportPage';
import { StatsPage } from './StatsPage';

/**
 * 报告与统计容器页。
 * 原来“统计”是独立 Tab，为了让 AI 管家有固定的底部入口，
 * 这里把「老人活动报告」和「周/月趋势统计」合并为一个 Tab，用顶部分段切换。
 */
@Component
export struct ReportHubPage {
  @State tab: number = 0;

  @Builder
  segment(index: number, label: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.tab === index ? '#FFFFFF' : Theme.SUB)
      .backgroundColor(this.tab === index ? Theme.PRIMARY : Theme.CARD)
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .borderRadius(16)
      .onClick(() => {
        this.tab = index;
      })
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        this.segment(0, '今日报告')
        this.segment(1, '趋势统计')
        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 4 })
      .alignItems(VerticalAlign.Center)

      Column() {
        if (this.tab === 0) {
          ReportPage()
        } else {
          StatsPage()
        }
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
  }
}
