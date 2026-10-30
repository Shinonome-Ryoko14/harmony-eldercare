import { AlertRecord, DeviceData } from '../common/Types';
import { Theme } from '../common/Theme';
import { Constants } from '../common/Constants';
import { ChatMessage, StreamCallbacks, UiMessage } from '../common/AiTypes';
import { ConfigStore } from '../store/ConfigStore';
import { AppStore } from '../store/AppStore';
import { AiBus } from '../store/AiBus';
import { AiService } from '../network/AiService';
import { AiContext, CareSnapshot } from '../data/AiContext';
import { AiRepository } from '../data/AiRepository';
import { Repository } from '../data/Repository';
import { AiConfigPanel } from '../components/AiConfigPanel';
import { AppIcon } from '../components/AppIcon';
import { pasteboard } from '@kit.BasicServicesKit';

const QUICK_PROMPTS: string[] = [
  '今天老人情况怎么样？',
  '最近活动量有下降吗？',
  '最近有哪些告警需要处理？',
  '帮我写一段发给家属的通知'
];

/**
 * AI 管家页。
 * - 每次提问自动携带实时数据、活动统计与告警上下文；
 * - 支持流式打字、停止、重试、复制、清空；
 * - 未配置 Key 时自动生成本地规则简报，保证离线演示可用；
 * - 从告警页跳转后可把 AI 建议一键写入处置记录。
 */
@Component
export struct AssistantPage {
  @State messages: UiMessage[] = [];
  @State input: string = '';
  @State generating: boolean = false;
  @State hasKey: boolean = false;
  @State showConfig: boolean = false;
  @State liveSummary: string = '正在读取实时数据…';

  private scroller: Scroller = new Scroller();
  private nextId: number = 1;
  private streamText: string = '';
  private flushTimer: number = -1;
  private keyTimer: number = -1;
  private scrollPending: boolean = false;
  private lastRequestTs: number = 0;
  private historyLoaded: boolean = false;
  private loadRetry: number = 0;
  private runSeq: number = 0;
  private pendingAlert: AlertRecord | null = null;
  private busSubscribed: boolean = false;

  private busListener: () => void = () => {
    this.consumePending();
  };

  aboutToAppear(): void {
    this.hasKey = ConfigStore.hasAiKey();
    this.refreshSummary();
    this.loadHistory();
    if (!this.busSubscribed) {
      AiBus.get().subscribe(this.busListener);
      this.busSubscribed = true;
    }
    if (this.keyTimer !== -1) {
      clearInterval(this.keyTimer);
    }
    this.keyTimer = setInterval(() => {
      this.hasKey = ConfigStore.hasAiKey();
      this.refreshSummary();
    }, 2000);
    setTimeout(() => {
      this.consumePending();
    }, 150);
  }

  aboutToDisappear(): void {
    if (this.busSubscribed) {
      AiBus.get().unsubscribe(this.busListener);
      this.busSubscribed = false;
    }
    if (this.keyTimer !== -1) {
      clearInterval(this.keyTimer);
      this.keyTimer = -1;
    }
    if (this.flushTimer !== -1) {
      clearTimeout(this.flushTimer);
      this.flushTimer = -1;
    }
  }

  // ---------------- 数据加载 ----------------

  /** 欢迎页顶部的一行实时摘要 */
  private refreshSummary(): void {
    let d: DeviceData | undefined = AppStore.get().current();
    if (d === undefined) {
      this.liveSummary = '暂无设备数据，请检查网关、WiFi 与上报地址';
      return;
    }
    let tempText: string = d.temp !== 0 ? `${d.temp}℃` : '温度暂无';
    let humiText: string = d.humi !== 0 ? `${d.humi}%` : '湿度暂无';
    this.liveSummary = `${d.online ? '设备在线' : '设备离线'} · ${tempText} · ${humiText} · ` +
      `门窗${d.door === 1 ? '开启' : '关闭'}`;
  }

  private async loadHistory(): Promise<void> {
    if (this.messages.length > 0) {
      this.historyLoaded = true;
      return;
    }
    let rows = await AiRepository.recent(Constants.AI_HISTORY_LOAD);
    if (this.generating || this.messages.length > 0) {
      this.historyLoaded = true;
      return;
    }
    if (rows.length === 0) {
      this.historyLoaded = true;
      return;
    }
    let list: UiMessage[] = [];
    for (let i: number = 0; i < rows.length; i++) {
      let role: string = rows[i].role;
      if (role !== 'user' && role !== 'assistant') {
        continue;
      }
      list.push({
        id: this.nextId,
        role: role,
        content: rows[i].content,
        error: false,
        streaming: false,
        adoptable: false
      });
      this.nextId = this.nextId + 1;
    }
    this.messages = list;
    this.historyLoaded = true;
    this.scrollToBottom();
  }

  /** 消费告警页传来的提问 */
  private consumePending(): void {
    if (!this.historyLoaded) {
      if (this.loadRetry < 20) {
        this.loadRetry = this.loadRetry + 1;
        setTimeout(() => {
          this.consumePending();
        }, 150);
      }
      return;
    }
    if (this.generating) {
      return;
    }
    let prompt: string = AiBus.get().consumePrompt();
    if (prompt.length === 0) {
      return;
    }
    this.pendingAlert = AiBus.get().getAlert();
    this.runQuery(prompt, true, true);
  }

  // ---------------- 发送与生成 ----------------

  private send(): void {
    if (this.generating) {
      return;
    }
    let text: string = this.input.trim();
    if (text.length === 0) {
      return;
    }
    this.runQuery(text, true, false);
  }

  private sendQuick(text: string): void {
    if (this.generating) {
      return;
    }
    this.runQuery(text, true, false);
  }

  private async sendLocalBrief(): Promise<void> {
    if (this.generating) {
      return;
    }
    this.pendingAlert = null;
    AiBus.get().clearAlert();
    this.runSeq = this.runSeq + 1;
    let seq: number = this.runSeq;
    this.generating = true;
    this.lastRequestTs = Date.now();
    let question: string = '生成今日照护简报（本地规则）';
    this.messages = this.messages.concat([this.newMessage('user', question)]);
    this.persist('user', question);
    let placeholder: UiMessage = this.newMessage('assistant', '');
    placeholder.streaming = true;
    this.messages = this.messages.concat([placeholder]);
    this.scrollToBottom();
    try {
      let snap: CareSnapshot = await AiContext.snapshot(AppStore.get().getSelectedDeviceNo());
      if (seq !== this.runSeq) {
        return;
      }
      this.finishAssistant(AiContext.brief(snap), true);
    } catch (e) {
      if (seq === this.runSeq) {
        this.failAssistant('生成本地简报失败，请稍后重试。');
      }
    }
  }

  private async runQuery(question: string, appendUser: boolean, keepAlert: boolean): Promise<void> {
    let q: string = question.trim();
    if (q.length === 0 || this.generating) {
      return;
    }
    let now: number = Date.now();
    if (!keepAlert && now - this.lastRequestTs < Constants.AI_MIN_INTERVAL) {
      this.toast('操作太频繁，请稍后再试');
      return;
    }
    this.lastRequestTs = now;
    if (!keepAlert) {
      this.pendingAlert = null;
      AiBus.get().clearAlert();
    }
    this.runSeq = this.runSeq + 1;
    let seq: number = this.runSeq;
    this.generating = true;
    this.input = '';

    if (appendUser) {
      this.messages = this.messages.concat([this.newMessage('user', q)]);
      this.persist('user', q);
    }

    let history: ChatMessage[] = this.buildHistory();
    let placeholder: UiMessage = this.newMessage('assistant', '');
    placeholder.streaming = true;
    this.messages = this.messages.concat([placeholder]);
    this.streamText = '';
    this.scrollToBottom();

    let snap: CareSnapshot = await AiContext.snapshot(AppStore.get().getSelectedDeviceNo());
    if (seq !== this.runSeq) {
      return;
    }

    if (!ConfigStore.hasAiKey()) {
      let prefix: string = '未配置模型 API Key，以下是本地规则生成的简报。点右上角的设置按钮可接入免费模型。\n\n';
      let local: string = AiContext.brief(snap);
      if (q.indexOf('通知') >= 0 || q.indexOf('家属') >= 0) {
        local = AiContext.notice(snap);
      }
      this.finishAssistant(prefix + local, true);
      return;
    }

    let system: ChatMessage = {
      role: 'system',
      content: `${Constants.AI_SYSTEM_PROMPT}\n\n【当前业务数据】\n${AiContext.prompt(snap)}`
    };
    let msgs: ChatMessage[] = [system];
    for (let i: number = 0; i < history.length; i++) {
      msgs.push(history[i]);
    }

    let cb: StreamCallbacks = {
      onDelta: (text: string) => {
        if (seq !== this.runSeq) {
          return;
        }
        this.streamText = this.streamText + text;
        this.scheduleFlush();
      },
      onDone: (full: string) => {
        if (seq !== this.runSeq) {
          return;
        }
        this.finishAssistant(full, true);
      },
      onError: (message: string) => {
        if (seq !== this.runSeq) {
          return;
        }
        this.failAssistant(message);
      }
    };
    try {
      await AiService.get().chat(msgs, cb);
    } catch (e) {
      if (seq === this.runSeq) {
        this.failAssistant(`请求失败：${(e as Error).message}`);
      }
    }
  }

  /** 取最近若干条成功消息作为多轮上下文 */
  private buildHistory(): ChatMessage[] {
    let history: ChatMessage[] = [];
    let start: number = this.messages.length - Constants.AI_HISTORY_TURNS;
    if (start < 0) {
      start = 0;
    }
    for (let i: number = start; i < this.messages.length; i++) {
      let m: UiMessage = this.messages[i];
      if (m.error || m.streaming || m.content.length === 0) {
        continue;
      }
      if (m.role === 'user' || m.role === 'assistant') {
        history.push({ role: m.role, content: m.content });
      }
    }
    return history;
  }

  private newMessage(role: string, content: string): UiMessage {
    let m: UiMessage = {
      id: this.nextId,
      role: role,
      content: content,
      error: false,
      streaming: false,
      adoptable: false
    };
    this.nextId = this.nextId + 1;
    return m;
  }

  private scheduleFlush(): void {
    if (this.flushTimer !== -1) {
      return;
    }
    this.flushTimer = setTimeout(() => {
      this.flushTimer = -1;
      this.applyStream();
    }, 80);
  }

  /** 流式渲染节流：把累计文本写进最后一条消息 */
  private applyStream(): void {
    let list: UiMessage[] = this.messages.slice(0, this.messages.length);
    if (list.length === 0) {
      return;
    }
    let last: UiMessage = list[list.length - 1];
    if (last.role !== 'assistant') {
      return;
    }
    list[list.length - 1] = {
      id: last.id,
      role: 'assistant',
      content: this.streamText,
      error: false,
      streaming: true,
      adoptable: false
    };
    this.messages = list;
    this.scrollToBottom();
  }

  private finishAssistant(full: string, persist: boolean): void {
    if (this.flushTimer !== -1) {
      clearTimeout(this.flushTimer);
      this.flushTimer = -1;
    }
    let text: string = full.length > 0 ? full : this.streamText;
    let isError: boolean = false;
    if (text.length === 0) {
      text = '模型没有返回内容，请点击重试。';
      isError = true;
    }
    let list: UiMessage[] = this.messages.slice(0, this.messages.length);
    if (list.length > 0) {
      let last: UiMessage = list[list.length - 1];
      list[list.length - 1] = {
        id: last.id,
        role: 'assistant',
        content: text,
        error: isError,
        streaming: false,
        adoptable: !isError && this.pendingAlert !== null
      };
      this.messages = list;
    }
    if (persist && !isError) {
      this.persist('assistant', text);
    }
    this.endGenerating();
  }

  private failAssistant(message: string): void {
    if (this.flushTimer !== -1) {
      clearTimeout(this.flushTimer);
      this.flushTimer = -1;
    }
    let text: string = this.streamText.length > 0 ? `${this.streamText}\n\n${message}` : message;
    let list: UiMessage[] = this.messages.slice(0, this.messages.length);
    if (list.length > 0) {
      let last: UiMessage = list[list.length - 1];
      list[list.length - 1] = {
        id: last.id,
        role: 'assistant',
        content: text,
        error: true,
        streaming: false,
        adoptable: false
      };
      this.messages = list;
    }
    this.endGenerating();
  }

  private stop(): void {
    if (!this.generating) {
      return;
    }
    this.runSeq = this.runSeq + 1;
    AiService.get().cancel();
    if (this.flushTimer !== -1) {
      clearTimeout(this.flushTimer);
      this.flushTimer = -1;
    }
    let partial: string = this.streamText;
    let text: string = partial.length > 0 ? `${partial}\n\n（已停止生成）` : '（已停止生成）';
    let list: UiMessage[] = this.messages.slice(0, this.messages.length);
    if (list.length > 0) {
      let last: UiMessage = list[list.length - 1];
      list[list.length - 1] = {
        id: last.id,
        role: 'assistant',
        content: text,
        error: false,
        streaming: false,
        adoptable: false
      };
      this.messages = list;
    }
    if (partial.length > 0) {
      this.persist('assistant', partial);
    }
    this.endGenerating();
  }

  private endGenerating(): void {
    this.generating = false;
    this.streamText = '';
    this.scrollToBottom();
    setTimeout(() => {
      this.consumePending();
    }, 400);
  }

  private retry(): void {
    if (this.generating) {
      return;
    }
    let q: string = '';
    for (let i: number = this.messages.length - 1; i >= 0; i--) {
      if (this.messages[i].role === 'user') {
        q = this.messages[i].content;
        break;
      }
    }
    if (q.length === 0) {
      return;
    }
    let list: UiMessage[] = this.messages.slice(0, this.messages.length);
    while (list.length > 0 && list[list.length - 1].role === 'assistant') {
      list.pop();
    }
    this.messages = list;
    this.runQuery(q, false, false);
  }

  private clearChat(): void {
    this.runSeq = this.runSeq + 1;
    if (this.generating) {
      AiService.get().cancel();
      this.generating = false;
    }
    this.messages = [];
    this.streamText = '';
    this.pendingAlert = null;
    AiBus.get().clearAlert();
    AiRepository.clear();
    this.toast('已清空对话');
  }

  private persist(role: string, content: string): void {
    AiRepository.add(AppStore.get().getSelectedDeviceNo(), role, content);
  }

  private async adopt(m: UiMessage): Promise<void> {
    let alert: AlertRecord | null = this.pendingAlert;
    if (alert === null) {
      this.toast('没有关联的告警，请在告警页点击「AI 解读」');
      return;
    }
    let result: string = m.content.trim();
    if (result.length > 280) {
      result = result.substring(0, 280) + '…';
    }
    try {
      await Repository.handleAlert(alert, `[AI建议] ${result}`, 'AI管家');
      this.pendingAlert = null;
      AiBus.get().clearAlert();
      let list: UiMessage[] = this.messages.slice(0, this.messages.length);
      for (let i: number = 0; i < list.length; i++) {
        if (list[i].id === m.id) {
          list[i] = {
            id: m.id,
            role: m.role,
            content: m.content,
            error: m.error,
            streaming: m.streaming,
            adoptable: false
          };
        }
      }
      this.messages = list;
      this.toast('已写入告警处置记录与安全日志');
    } catch (e) {
      console.error(`写入 AI 处置建议失败: ${JSON.stringify(e)}`);
      this.toast('写入失败，请稍后重试');
    }
  }

  private async copyText(text: string): Promise<void> {
    try {
      let data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard().setData(data);
      this.toast('已复制');
    } catch (e) {
      this.toast('复制失败');
    }
  }

  private scrollToBottom(): void {
    if (this.scrollPending) {
      return;
    }
    this.scrollPending = true;
    setTimeout(() => {
      this.scrollPending = false;
      try {
        this.scroller.scrollEdge(Edge.Bottom);
      } catch (e) {
        // 列表尚未布局完成时忽略
      }
    }, 80);
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (err) {
      console.error(`提示弹出失败: ${JSON.stringify(err)}`);
    }
  }

  /** 轻量去 Markdown 标记，避免气泡里出现 ** / ### 等符号 */
  private displayText(m: UiMessage): string {
    if (m.role !== 'assistant') {
      return m.content;
    }
    let t: string = m.content;
    t = t.split('**').join('');
    t = t.split('### ').join('');
    t = t.split('## ').join('');
    t = t.split('# ').join('');
    t = t.split('`').join('');
    return m.streaming ? `${t}▍` : t;
  }

  // ---------------- UI ----------------

  @Builder
  header() {
    Row() {
      Column({ space: 2 }) {
        Text('AI 管家')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT)
        Row() {
          Column()
            .width(7)
            .height(7)
            .borderRadius(4)
            .backgroundColor(this.hasKey ? Theme.OK : Theme.WARN)
          Text(this.hasKey ? '模型已配置' : '未配置模型 · 可用本地简报')
            .fontSize(11)
            .fontColor(this.hasKey ? Theme.OK : Theme.WARN)
            .margin({ left: 5 })
        }
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('清空')
        .fontSize(12)
        .fontColor(Theme.SUB)
        .padding(8)
        .onClick(() => {
          this.clearChat();
        })
      Stack() {
        AppIcon({ name: 'settings', iconSize: 19, color: Theme.TEXT, weight: 1.8 })
      }
      .width(36)
      .height(36)
      .borderRadius(11)
      .backgroundColor(Theme.CHIP)
      .margin({ left: 2 })
      .onClick(() => {
        this.showConfig = true;
      })
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: 12, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  welcome() {
    Scroll() {
      Column({ space: 12 }) {
        Stack() {
          Row()
            .width(82)
            .height(82)
            .borderRadius(41)
            .linearGradient({
              angle: 145,
              colors: [[Theme.PRIMARY_SOFT, 0.0], [Theme.alpha(Theme.PRIMARY, 0.16), 1.0]]
            })
          AppIcon({ name: 'ai', iconSize: 36, color: Theme.PRIMARY, weight: 1.5 })
        }
        .width(82)
        .height(82)
        .margin({ top: 20 })

        Text('居家守护 AI 管家')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT)
        Text('我会结合实时传感器、活动统计和告警记录回答，\n也可以帮你整理照护简报和家属通知。')
          .fontSize(13)
          .fontColor(Theme.SUB)
          .lineHeight(20)
          .textAlign(TextAlign.Center)

        Row({ space: 8 }) {
          Stack() {
            AppIcon({ name: 'signal', iconSize: 15, color: Theme.PRIMARY, weight: 1.8 })
          }
          .width(26)
          .height(26)
          .borderRadius(8)
          .backgroundColor(Theme.PRIMARY_SOFT)
          Text(this.liveSummary)
            .fontSize(12)
            .fontColor(Theme.SUB)
            .layoutWeight(1)
        }
        .width('100%')
        .padding(12)
        .backgroundColor(Theme.CARD)
        .borderRadius(14)
        .border({ width: 1, color: Theme.HAIRLINE })
        .alignItems(VerticalAlign.Center)

        if (!this.hasKey) {
          Row() {
            Column({ space: 2 }) {
              Text('尚未配置模型')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.TEXT)
              Text('内置智谱 GLM-4-Flash 免费模型，填写 Key 即可使用')
                .fontSize(11)
                .fontColor(Theme.SUB)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Text('去配置')
              .fontSize(12)
              .fontColor('#FFFFFF')
              .backgroundColor(Theme.PRIMARY)
              .padding({ left: 12, right: 12, top: 7, bottom: 7 })
              .borderRadius(9)
              .onClick(() => {
                this.showConfig = true;
              })
          }
          .width('100%')
          .padding(14)
          .backgroundColor(Theme.CARD)
          .borderRadius(16)
          .border({ width: 1, color: Theme.HAIRLINE })
          .alignItems(VerticalAlign.Center)
        }

        Column({ space: 8 }) {
          Text('你可以这样问')
            .fontSize(12)
            .fontColor(Theme.SUB)
            .width('100%')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(QUICK_PROMPTS, (q: string) => {
              Text(q)
                .fontSize(13)
                .fontColor(Theme.PRIMARY)
                .backgroundColor(Theme.PRIMARY_SOFT)
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .borderRadius(10)
                .margin({ right: 8, top: 6 })
                .onClick(() => {
                  this.sendQuick(q);
                })
            }, (q: string) => q)
          }
          .width('100%')
        }
        .width('100%')
        .padding(14)
        .backgroundColor(Theme.CARD)
        .borderRadius(16)
        .border({ width: 1, color: Theme.HAIRLINE })
        .alignItems(HorizontalAlign.Start)

        Row() {
          AppIcon({ name: 'doc', iconSize: 16, color: Theme.PRIMARY_DARK, weight: 1.8 })
          Text('生成本地照护简报（无需 Key）')
            .fontSize(13)
            .fontColor(Theme.PRIMARY_DARK)
            .margin({ left: 6 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding(12)
        .backgroundColor(Theme.GLASS)
        .borderRadius(14)
        .border({ width: 1, color: Theme.HAIRLINE })
        .onClick(() => {
          this.sendLocalBrief();
        })

        Text('AI 建议仅供参考，紧急情况请立即拨打 120 或联系家属。')
          .fontSize(10)
          .fontColor(Theme.SUB)
          .textAlign(TextAlign.Center)
          .margin({ top: 4, bottom: 20 })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
  }

  @Builder
  bubble(m: UiMessage) {
    Row() {
      if (m.role === 'assistant') {
        Stack() {
          AppIcon({ name: 'ai', iconSize: 16, color: Theme.PRIMARY, weight: 1.8 })
        }
        .width(28)
        .height(28)
        .borderRadius(9)
        .backgroundColor(Theme.PRIMARY_SOFT)
        .margin({ right: 8, top: 2 })
        .alignSelf(ItemAlign.Start)
      }
      Column({ space: 0 }) {
        if (m.role === 'assistant' && m.streaming && m.content.length === 0) {
          Text('正在思考…')
            .fontSize(14)
            .fontColor(Theme.SUB)
        } else {
          Text(this.displayText(m))
            .fontSize(14)
            .lineHeight(21)
            .fontColor(m.role === 'user' ? '#FFFFFF' : (m.error ? Theme.DANGER : Theme.TEXT))
            .textAlign(TextAlign.Start)
            .copyOption(CopyOptions.LocalDevice)
        }

        if (m.role === 'assistant' && !m.streaming) {
          Row({ space: 14 }) {
            Row() {
              AppIcon({ name: 'copy', iconSize: 13, color: Theme.SUB })
              Text('复制')
                .fontSize(11)
                .fontColor(Theme.SUB)
                .margin({ left: 3 })
            }
            .onClick(() => {
              this.copyText(m.content);
            })

            if (m.error) {
              Row() {
                AppIcon({ name: 'retry', iconSize: 13, color: Theme.PRIMARY })
                Text('重试')
                  .fontSize(11)
                  .fontColor(Theme.PRIMARY)
                  .margin({ left: 3 })
              }
              .onClick(() => {
                this.retry();
              })

              Row() {
                AppIcon({ name: 'doc', iconSize: 13, color: Theme.PRIMARY_DARK })
                Text('本地简报')
                  .fontSize(11)
                  .fontColor(Theme.PRIMARY_DARK)
                  .margin({ left: 3 })
              }
              .onClick(() => {
                this.sendLocalBrief();
              })
            }
            if (m.adoptable) {
              Row() {
                AppIcon({ name: 'check', iconSize: 13, color: Theme.PRIMARY_DARK })
                Text('写入处置记录')
                  .fontSize(11)
                  .fontColor(Theme.PRIMARY_DARK)
                  .margin({ left: 3 })
              }
              .onClick(() => {
                this.adopt(m);
              })
            }
          }
          .margin({ top: 8 })
          .alignItems(VerticalAlign.Center)
        }
      }
      .padding(12)
      .backgroundColor(m.role === 'user' ? Theme.PRIMARY : Theme.CARD)
      .borderRadius({
        topLeft: m.role === 'user' ? 16 : 6,
        topRight: m.role === 'user' ? 6 : 16,
        bottomLeft: 16,
        bottomRight: 16
      })
      .border({ width: m.role === 'user' ? 0 : 1, color: Theme.HAIRLINE })
      .shadow({ radius: 10, color: Theme.SHADOW, offsetX: 0, offsetY: 3 })
      .constraintSize({ maxWidth: '78%' })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .justifyContent(m.role === 'user' ? FlexAlign.End : FlexAlign.Start)
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  inputBar() {
    Column() {
      Row({ space: 10 }) {
        TextInput({ placeholder: this.generating ? '正在生成…' : '问问 AI 管家…', text: this.input })
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .backgroundColor(Theme.INPUT)
          .borderRadius(12)
          .padding({ left: 14, right: 14 })
          .enabled(!this.generating)
          .onChange((v: string) => {
            this.input = v;
          })
          .onSubmit(() => {
            this.send();
          })
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          AppIcon({
            name: this.generating ? 'stop' : 'send',
            iconSize: 19,
            color: '#FFFFFF',
            weight: 1.8,
            filled: this.generating
          })
        }
        .width(42)
        .height(42)
        .backgroundColor(this.generating ? Theme.DANGER : Theme.PRIMARY)
        .opacity(this.generating || this.input.trim().length > 0 ? 1 : 0.45)
        .enabled(this.generating || this.input.trim().length > 0)
        .onClick(() => {
          if (this.generating) {
            this.stop();
          } else {
            this.send();
          }
        })
      }
      .width('100%')

      Text('AI 建议仅供参考，紧急情况请立即拨打 120 或联系家属')
        .fontSize(10)
        .fontColor(Theme.SUB)
        .margin({ top: 6 })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 9, bottom: 9 })
    .backgroundColor(Theme.GLASS)
    .border({ width: { top: 1 }, color: Theme.HAIRLINE })
  }

  @Builder
  configOverlay() {
    Column() {
      Column() {
        Row() {
          Text('AI 模型设置')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TEXT)
            .layoutWeight(1)
          Text('关闭')
            .fontSize(13)
            .fontColor(Theme.SUB)
            .onClick(() => {
              this.showConfig = false;
            })
        }
        .width('100%')
        .margin({ bottom: 12 })

        Scroll() {
          AiConfigPanel({
            onSaved: () => {
              this.showConfig = false;
              this.hasKey = ConfigStore.hasAiKey();
              this.toast('AI 配置已保存');
            }
          })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)
      }
      .width('92%')
      .height('78%')
      .padding(18)
      .backgroundColor(Theme.CARD)
      .borderRadius(22)
      .border({ width: 1, color: Theme.HAIRLINE })
      .shadow({ radius: 28, color: Theme.SHADOW_STRONG, offsetX: 0, offsetY: 12 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(16, 32, 34, 0.32)')
    .backdropBlur(8)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Stack() {
      Column() {
        this.header()

        if (this.messages.length === 0) {
          this.welcome()
        } else {
          List({ scroller: this.scroller, space: 12 }) {
            ForEach(this.messages, (m: UiMessage) => {
              ListItem() {
                this.bubble(m)
              }
            }, (m: UiMessage) => `${m.id}-${m.content.length}-${m.streaming ? 1 : 0}`)
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 16, right: 16, top: 4, bottom: 8 })
          .scrollBar(BarState.Off)
        }

        this.inputBar()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.BG)

      if (this.showConfig) {
        this.configOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }
}
