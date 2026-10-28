import { Theme } from '../common/Theme';
import { AiBus } from '../store/AiBus';
import { RealtimePage } from './RealtimePage';
import { ReportHubPage } from './ReportHubPage';
import { AlertPage } from './AlertPage';
import { AssistantPage } from './AssistantPage';
import { LogPage } from './LogPage';
import { SettingsPage } from './SettingsPage';

/** AI 管家的 Tab 下标（告警页跳转时使用） */
const AI_TAB_INDEX: number = 3;

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  private controller: TabsController = new TabsController();

  private aiBusListener: () => void = () => {
    // 告警页请求 AI 解读时，自动切到 AI Tab
    try {
      this.controller.changeIndex(AI_TAB_INDEX);
    } catch (e) {
      console.error(`切换 AI Tab 失败: ${JSON.stringify(e)}`);
    }
  };

  aboutToAppear(): void {
    AiBus.get().subscribe(this.aiBusListener);
  }

  aboutToDisappear(): void {
    AiBus.get().unsubscribe(this.aiBusListener);
  }

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
        ReportHubPage()
      }
      .tabBar(this.tabItem(1, '📊', '报告'))

      TabContent() {
        AlertPage()
      }
      .tabBar(this.tabItem(2, '🔔', '告警'))

      TabContent() {
        AssistantPage()
      }
      .tabBar(this.tabItem(3, '🤖', 'AI'))

      TabContent() {
        LogPage()
      }
      .tabBar(this.tabItem(4, '📝', '日志'))

      TabContent() {
        SettingsPage()
      }
      .tabBar(this.tabItem(5, '⚙️', '设置'))
    }
    .barMode(BarMode.Fixed)
    .backgroundColor(Theme.BG)
    .onChange((index: number) => {
      this.currentIndex = index;
    })
  }
}
