import { Theme } from '../common/Theme';
import { AiConfig, AiPreset, AI_PRESETS } from '../common/AiTypes';
import { ConfigStore } from '../store/ConfigStore';
import { AiService } from '../network/AiService';

/**
 * AI 模型配置面板（设置页与 AI 页共用）。
 * 统一走 OpenAI 兼容协议，内置智谱 / 硅基流动免费模型预设。
 */

function findPreset(baseUrl: string, model: string): number {
  for (let i: number = 0; i < AI_PRESETS.length; i++) {
    if (AI_PRESETS[i].baseUrl === baseUrl.trim() && AI_PRESETS[i].model === model.trim()) {
      return i;
    }
  }
  return -1;
}

@Component
export struct AiConfigPanel {
  @State baseUrl: string = '';
  @State model: string = '';
  @State apiKey: string = '';
  @State stream: boolean = true;
  @State testing: boolean = false;
  @State activePreset: number = -1;
  onSaved: () => void = () => {
  };

  aboutToAppear(): void {
    let cfg: AiConfig = ConfigStore.getAiConfig();
    this.baseUrl = cfg.baseUrl;
    this.model = cfg.model;
    this.apiKey = cfg.apiKey;
    this.stream = cfg.stream;
    this.activePreset = findPreset(cfg.baseUrl, cfg.model);
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (err) {
      console.error(`提示弹出失败: ${JSON.stringify(err)}`);
    }
  }

  private applyPreset(p: AiPreset, index: number): void {
    this.baseUrl = p.baseUrl;
    this.model = p.model;
    this.activePreset = index;
  }

  private currentConfig(): AiConfig {
    return {
      baseUrl: this.baseUrl.trim(),
      model: this.model.trim(),
      apiKey: this.apiKey.trim(),
      stream: this.stream,
      temperature: ConfigStore.getAiConfig().temperature
    };
  }

  private async save(): Promise<void> {
    let cfg: AiConfig = this.currentConfig();
    if (cfg.baseUrl.length === 0 || cfg.model.length === 0) {
      this.toast('请填写 Base URL 与模型名');
      return;
    }
    if (!cfg.baseUrl.startsWith('http://') && !cfg.baseUrl.startsWith('https://')) {
      this.toast('Base URL 必须以 http:// 或 https:// 开头');
      return;
    }
    await ConfigStore.saveAiConfig(cfg);
    this.activePreset = findPreset(cfg.baseUrl, cfg.model);
    this.onSaved();
  }

  private async test(): Promise<void> {
    if (this.testing) {
      return;
    }
    let cfg: AiConfig = this.currentConfig();
    if (cfg.apiKey.length === 0) {
      this.toast('请先填写 API Key');
      return;
    }
    this.testing = true;
    try {
      let reply: string = await AiService.test(cfg);
      let short: string = reply.length > 40 ? reply.substring(0, 40) : reply;
      this.toast(`连接成功：${short}`);
    } catch (err) {
      let msg: string = (err as Error).message;
      this.toast(msg.length > 80 ? msg.substring(0, 80) : msg);
    } finally {
      this.testing = false;
    }
  }

  build() {
    Column({ space: 10 }) {
      Text('选择免费模型')
        .fontSize(12)
        .fontColor(Theme.SUB)
        .width('100%')

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(AI_PRESETS, (p: AiPreset, index: number) => {
          Text(p.name)
            .fontSize(12)
            .fontColor(this.activePreset === index ? '#FFFFFF' : Theme.PRIMARY)
            .backgroundColor(this.activePreset === index ? Theme.PRIMARY : '#E0F2F1')
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(14)
            .margin({ right: 8, top: 6 })
            .onClick(() => {
              this.applyPreset(p, index);
            })
        }, (p: AiPreset) => p.name)
      }
      .width('100%')

      if (this.activePreset >= 0) {
        Text(`${AI_PRESETS[this.activePreset].hint} · 免费额度以平台控制台为准`)
          .fontSize(11)
          .fontColor(Theme.SUB)
          .width('100%')
      }

      Text('智谱 Key 获取：open.bigmodel.cn → 控制台 → API Keys')
        .fontSize(10)
        .fontColor(Theme.SUB)
        .width('100%')

      Column({ space: 4 }) {
        Text('Base URL')
          .fontSize(12)
          .fontColor(Theme.SUB)
          .width('100%')
        TextInput({ placeholder: 'https://open.bigmodel.cn/api/paas/v4', text: this.baseUrl })
          .width('100%')
          .height(38)
          .fontSize(13)
          .onChange((v: string) => {
            this.baseUrl = v;
            this.activePreset = -1;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 4 }) {
        Text('模型名')
          .fontSize(12)
          .fontColor(Theme.SUB)
          .width('100%')
        TextInput({ placeholder: 'glm-4-flash', text: this.model })
          .width('100%')
          .height(38)
          .fontSize(13)
          .onChange((v: string) => {
            this.model = v;
            this.activePreset = -1;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 4 }) {
        Text('API Key')
          .fontSize(12)
          .fontColor(Theme.SUB)
          .width('100%')
        TextInput({ placeholder: '在平台控制台创建，仅保存在本机', text: this.apiKey })
          .width('100%')
          .height(38)
          .fontSize(13)
          .type(InputType.Password)
          .showPasswordIcon(true)
          .onChange((v: string) => {
            this.apiKey = v;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Row() {
        Column() {
          Text('流式输出')
            .fontSize(13)
            .fontColor(Theme.TEXT)
          Text('失败会自动降级为普通请求')
            .fontSize(11)
            .fontColor(Theme.SUB)
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.stream })
          .selectedColor(Theme.PRIMARY)
          .onChange((isOn: boolean) => {
            this.stream = isOn;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 10 }) {
        Button(this.testing ? '测试中...' : '测试连接')
          .layoutWeight(1)
          .height(38)
          .fontSize(13)
          .backgroundColor('#E0F2F1')
          .fontColor(Theme.PRIMARY)
          .enabled(!this.testing)
          .onClick(() => {
            this.test();
          })
        Button('保存配置')
          .layoutWeight(1)
          .height(38)
          .fontSize(13)
          .backgroundColor(Theme.PRIMARY)
          .onClick(() => {
            this.save();
          })
      }
      .width('100%')

      Text('Key 只在手机本地保存，不会上传到本 App 的服务器；请勿把 Key 写进代码或提交到 Git。')
        .fontSize(10)
        .fontColor(Theme.SUB)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
