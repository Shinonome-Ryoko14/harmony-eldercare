import { AlertRecord } from '../common/Types';

/**
 * 告警页 -> AI 页的轻量消息总线。
 * 告警页调用 ask() 后，底部导航切到 AI Tab，AI 页消费待处理问题。
 */
export class AiBus {
  private static instance: AiBus | null = null;

  private pendingPrompt: string = '';
  private pendingAlert: AlertRecord | null = null;
  private listeners: (() => void)[] = [];

  static get(): AiBus {
    if (AiBus.instance === null) {
      AiBus.instance = new AiBus();
    }
    return AiBus.instance;
  }

  /**
   * 请求 AI 解读。
   * @param prompt 预置提问
   * @param alert 关联告警（可空），用于“把建议写入处置记录”
   */
  ask(prompt: string, alert: AlertRecord | null): void {
    this.pendingPrompt = prompt;
    this.pendingAlert = alert;
    this.emit();
  }

  /** 取出待处理提问（取走后清空） */
  consumePrompt(): string {
    let p: string = this.pendingPrompt;
    this.pendingPrompt = '';
    return p;
  }

  getAlert(): AlertRecord | null {
    return this.pendingAlert;
  }

  clearAlert(): void {
    this.pendingAlert = null;
  }

  subscribe(listener: () => void): void {
    this.listeners.push(listener);
  }

  unsubscribe(listener: () => void): void {
    let idx: number = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  private emit(): void {
    this.listeners.forEach((l: () => void) => {
      l();
    });
  }
}
