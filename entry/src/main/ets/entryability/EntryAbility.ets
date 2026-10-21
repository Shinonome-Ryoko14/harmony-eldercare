import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { RdbHelper } from '../data/RdbHelper';
import { ConfigStore } from '../store/ConfigStore';
import { HttpService } from '../network/HttpService';
import { UsbSerialService } from '../network/UsbSerialService';

const DOMAIN: number = 0x0000;
const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    hilog.info(DOMAIN, TAG, 'onCreate');
    // 先初始化数据库与配置，再启动轮询，避免首轮写库时数据库尚未就绪
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
    HttpService.get().start().catch((e: BusinessError) => {
      hilog.error(DOMAIN, TAG, `HTTP 服务启动失败: ${e.code} ${e.message}`);
    });
  }

  onDestroy(): void {
    HttpService.get().stop();
    UsbSerialService.get().close();
    hilog.info(DOMAIN, TAG, 'onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, `加载页面失败: ${err.code} ${err.message}`);
        return;
      }
      hilog.info(DOMAIN, TAG, '页面加载完成');
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
