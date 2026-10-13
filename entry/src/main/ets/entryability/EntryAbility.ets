import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { RdbHelper } from '../data/RdbHelper';
import { ConfigStore } from '../store/ConfigStore';
import { HttpService } from '../network/HttpService';

const DOMAIN: number = 0x0000;
const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    hilog.info(DOMAIN, TAG, 'onCreate');
    try {
      await RdbHelper.init(this.context);
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      hilog.error(DOMAIN, TAG, `数据库初始化失败: ${err.code} ${err.message}`);
    }
    try {
      await ConfigStore.init(this.context);
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      hilog.error(DOMAIN, TAG, `配置初始化失败: ${err.code} ${err.message}`);
    }
  }

  onDestroy(): void {
    HttpService.get().stop();
    hilog.info(DOMAIN, TAG, 'onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, `加载页面失败: ${err.code} ${err.message}`);
        return;
      }
      HttpService.get().start().catch((e: BusinessError) => {
        hilog.error(DOMAIN, TAG, `HTTP 服务启动失败: ${e.code} ${e.message}`);
      });
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageDestroy');
  }

  onForeground(): void {
    HttpService.get().start().catch((e: BusinessError) => {
      hilog.error(DOMAIN, TAG, `HTTP 服务启动失败: ${e.code} ${e.message}`);
    });
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'onBackground');
  }
}
