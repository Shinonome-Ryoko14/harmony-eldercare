import { Theme } from '../common/Theme';
import { RealtimePage } from './RealtimePage';
import { ReportPage } from './ReportPage';
import { AlertPage } from './AlertPage';
import { StatsPage } from './StatsPage';
import { LogPage } from './LogPage';

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  private controller: TabsController = new TabsController();

  @Builder
  tabItem(index: number, icon: string, label: string) {
    Column() {
      Text(icon)
        .fontSize(22)
        .opacity(this.currentIndex === index ? 1 : 0.5)
      Text(label)
        .fontSize(11)
        .fontColor(this.currentIndex === index ? Theme.PRIMARY : Theme.SUB)
        .margin({ top: 2 })
    }
    .width('100%')
    .height(52)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Tabs({ barPosition: BarPosition.End, controller: this.controller }) {
      TabContent() {
        RealtimePage()
      }
      .tabBar(this.tabItem(0, '🏠', '实时'))

      TabContent() {
        ReportPage()
      }
      .tabBar(this.tabItem(1, '📊', '报告'))

      TabContent() {
        AlertPage()
      }
      .tabBar(this.tabItem(2, '🔔', '告警'))

      TabContent() {
        StatsPage()
      }
      .tabBar(this.tabItem(3, '📈', '统计'))

      TabContent() {
        LogPage()
      }
      .tabBar(this.tabItem(4, '📝', '日志'))
    }
    .barMode(BarMode.Fixed)
    .backgroundColor(Theme.BG)
    .onChange((index: number) => {
      this.currentIndex = index;
    })
  }
}
