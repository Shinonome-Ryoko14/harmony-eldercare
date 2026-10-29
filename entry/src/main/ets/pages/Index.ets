import { Theme } from '../common/Theme';
import { AiBus } from '../store/AiBus';
import { AppIcon } from '../components/AppIcon';
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
      Stack() {
        Row()
          .width(34)
          .height(24)
          .borderRadius(9)
          .backgroundColor(this.currentIndex === index ? Theme.PRIMARY_SOFT : Color.Transparent)
          .animation({ duration: 180, curve: Curve.EaseOut })
        AppIcon({
          name: icon,
          size: 19,
          color: this.currentIndex === index ? Theme.PRIMARY : Theme.SUB,
          weight: this.currentIndex === index ? 1.9 : 1.6
        })
      }
      .width(34)
      .height(24)

      Text(label)
        .fontSize(10)
        .fontColor(this.currentIndex === index ? Theme.PRIMARY : Theme.SUB)
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
        .margin({ top: 3 })
    }
    .width('100%')
    .height(56)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Tabs({ barPosition: BarPosition.End, controller: this.controller }) {
      TabContent() {
        RealtimePage()
      }
      .tabBar(this.tabItem(0, 'home', '实时'))

      TabContent() {
        ReportHubPage()
      }
      .tabBar(this.tabItem(1, 'report', '报告'))

      TabContent() {
        AlertPage()
      }
      .tabBar(this.tabItem(2, 'bell', '告警'))

      TabContent() {
        AssistantPage()
      }
      .tabBar(this.tabItem(3, 'chat', 'AI'))

      TabContent() {
        LogPage()
      }
      .tabBar(this.tabItem(4, 'doc', '日志'))

      TabContent() {
        SettingsPage()
      }
      .tabBar(this.tabItem(5, 'settings', '设置'))
    }
    .barMode(BarMode.Fixed)
    .barHeight(58)
    .barBackgroundColor('rgba(255, 255, 255, 0.82)')
    .barBackgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .backgroundColor(Theme.BG)
    .onChange((index: number) => {
      this.currentIndex = index;
    })
  }
}
