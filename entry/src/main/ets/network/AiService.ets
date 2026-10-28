import http from '@ohos.net.http';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { AiConfig, ChatMessage, StreamCallbacks } from '../common/AiTypes';
import { ConfigStore } from '../store/ConfigStore';
import { Constants } from '../common/Constants';

/** 发往 OpenAI 兼容接口的请求体 */
interface ChatRequestBody {
  model: string;
  messages: ChatMessage[];
  stream: boolean;
  temperature: number;
  max_tokens: number;
}

/** 流式请求的最终结果 */
interface StreamOutcome {
  /** 是否已由流式流程处理完成（成功拿到响应） */
  handled: boolean;
  /** 是否已向界面输出过内容 */
  emitted: boolean;
  content: string;
  error: string;
}

/**
 * AI 模型服务（OpenAI 兼容协议）。
 *
 * - 默认走 SSE 流式：requestInStream + dataReceive，逐字回调；
 * - 流式失败（模拟器不支持 / 网关返回非 SSE / 非 200）自动降级为非流式 request；
 * - 支持取消、看门狗超时、429/401 等中文错误提示；
 * - 同一时间只允许一个请求。
 */
export class AiService {
  private static instance: AiService | null = null;

  private current: http.HttpRequest | null = null;
  private cancelled: boolean = false;
  private abortHandler: (() => void) | null = null;

  static get(): AiService {
    if (AiService.instance === null) {
      AiService.instance = new AiService();
    }
    return AiService.instance;
  }

  isBusy(): boolean {
    return this.current !== null;
  }

  /** 停止当前生成（页面“停止”按钮） */
  cancel(): void {
    this.cancelled = true;
    let handler: (() => void) | null = this.abortHandler;
    this.abortHandler = null;
    if (handler !== null) {
      handler();
    }
    let req: http.HttpRequest | null = this.current;
    this.current = null;
    if (req !== null) {
      try {
        req.destroy();
      } catch (e) {
        console.error(`取消 AI 请求失败: ${JSON.stringify(e)}`);
      }
    }
  }

  /**
   * 发送对话。流式时内容通过 onDelta 增量回调，结束后 onDone 返回完整文本。
   */
  async chat(messages: ChatMessage[], cb: StreamCallbacks): Promise<void> {
    this.cancelled = false;
    let cfg: AiConfig = ConfigStore.getAiConfig();
    if (cfg.apiKey.trim().length === 0) {
      cb.onError('尚未配置模型 API Key。请点右上角 ⚙️ 选择免费模型并填写 Key。');
      return;
    }
    if (cfg.baseUrl.trim().length === 0 || cfg.model.trim().length === 0) {
      cb.onError('模型配置不完整，请检查 Base URL 与模型名。');
      return;
    }
    if (!cfg.stream) {
      await this.nonStream(messages, cfg, cb);
      return;
    }

    let outcome: StreamOutcome = await this.streamToEnd(messages, cfg, cb);
    if (this.cancelled) {
      return;
    }
    if (outcome.handled) {
      if (outcome.content.length > 0) {
        cb.onDone(outcome.content);
      } else {
        // 流式返回为空，尝试普通请求兜底
        await this.nonStream(messages, cfg, cb);
      }
      return;
    }
    if (outcome.emitted) {
      cb.onError(outcome.error.length > 0 ? outcome.error : '生成中断，请重试。');
      return;
    }
    // 无任何输出：自动降级为非流式，兼容模拟器或部分网关
    await this.nonStream(messages, cfg, cb);
  }

  // ---------------- 流式请求 ----------------

  private streamToEnd(messages: ChatMessage[], cfg: AiConfig, cb: StreamCallbacks): Promise<StreamOutcome> {
    return new Promise<StreamOutcome>((resolve: (value: StreamOutcome) => void) => {
      let req: http.HttpRequest = http.createHttp();
      this.current = req;

      let buffer: string = '';
      let rawBuffer: string = '';
      let full: string = '';
      let settled: boolean = false;
      let watchdog: number = -1;
      let decoderOptions: util.TextDecoderOptions = { fatal: false, ignoreBOM: true };
      let decoder: util.TextDecoder = util.TextDecoder.create('utf-8', decoderOptions);

      let cleanup = (): void => {
        if (watchdog !== -1) {
          clearTimeout(watchdog);
          watchdog = -1;
        }
        try {
          req.off('dataReceive');
        } catch (e) {
          // 忽略取消订阅失败
        }
        try {
          req.off('dataEnd');
        } catch (e) {
          // 忽略取消订阅失败
        }
        try {
          req.destroy();
        } catch (e) {
          // 忽略销毁失败
        }
        if (this.current === req) {
          this.current = null;
        }
        this.abortHandler = null;
      };

      let finish = (ok: boolean, error: string): void => {
        if (settled) {
          return;
        }
        settled = true;
        cleanup();
        if (ok) {
          // 少数网关在 stream=true 时仍返回普通 JSON
          if (full.length === 0) {
            let plain: string = AiService.parsePlainContent(rawBuffer);
            if (plain.length > 0) {
              full = plain;
              cb.onDelta(plain);
            }
          }
          resolve({ handled: true, emitted: full.length > 0, content: full, error: '' });
        } else {
          resolve({ handled: false, emitted: full.length > 0, content: full, error: error });
        }
      };

      let consume = (text: string, isFinal: boolean): void => {
        rawBuffer += text;
        buffer += text;
        let lines: string[] = buffer.split('\n');
        if (isFinal) {
          buffer = '';
        } else {
          buffer = lines.pop() ?? '';
        }
        for (let i: number = 0; i < lines.length; i++) {
          let line: string = lines[i].trim();
          if (line.length === 0) {
            continue;
          }
          if (line.indexOf('data:') !== 0) {
            continue;
          }
          let payload: string = line.substring(5).trim();
          if (payload.length === 0) {
            continue;
          }
          if (payload === '[DONE]') {
            finish(true, '');
            return;
          }
          try {
            let obj: Record<string, Object> = JSON.parse(payload) as Record<string, Object>;
            let errValue: Object | undefined = obj['error'];
            if (errValue !== undefined && errValue !== null) {
              finish(false, AiService.extractErrorMessage(payload));
              return;
            }
            let delta: string = AiService.extractDelta(obj);
            if (delta.length > 0) {
              full += delta;
              cb.onDelta(delta);
            }
          } catch (e) {
            // 单个分片解析失败不致命，继续等待后续数据
          }
        }
      };

      req.on('dataReceive', (data: ArrayBuffer) => {
        if (settled || this.cancelled) {
          return;
        }
        let chunk: string = '';
        try {
          let decodeOptions: util.DecodeToStringOptions = { stream: true };
          chunk = decoder.decodeToString(new Uint8Array(data), decodeOptions);
        } catch (e) {
          return;
        }
        consume(chunk, false);
      });

      req.on('dataEnd', () => {
        if (settled || this.cancelled) {
          return;
        }
        consume('', true);
        finish(true, '');
      });

      this.abortHandler = (): void => {
        finish(false, '');
      };

      watchdog = setTimeout(() => {
        if (!settled) {
          finish(false, 'AI 回复超时，请检查网络后重试。');
        }
      }, Constants.AI_STREAM_TIMEOUT);

      req.requestInStream(AiService.endpoint(cfg), AiService.options(cfg, messages, true))
        .then((code: number) => {
          if (settled || this.cancelled) {
            return;
          }
          if (code !== 200) {
            finish(false, AiService.statusMessage(code, ''));
          }
        })
        .catch((err: BusinessError) => {
          if (settled || this.cancelled) {
            return;
          }
          finish(false, AiService.networkError(err));
        });
    });
  }

  // ---------------- 非流式请求 ----------------

  private async nonStream(messages: ChatMessage[], cfg: AiConfig, cb: StreamCallbacks): Promise<void> {
    if (this.cancelled) {
      return;
    }
    let req: http.HttpRequest = http.createHttp();
    this.current = req;
    try {
      let resp: http.HttpResponse = await req.request(AiService.endpoint(cfg),
        AiService.options(cfg, messages, false));
      if (this.cancelled) {
        return;
      }
      let text: string = AiService.resultText(resp.result);
      if (resp.responseCode !== 200) {
        cb.onError(AiService.statusMessage(resp.responseCode, text));
        return;
      }
      let content: string = AiService.parsePlainContent(text);
      if (content.length === 0) {
        let bizError: string = AiService.errorMessageIfAny(text);
        cb.onError(bizError.length > 0 ? bizError : '模型没有返回内容，请检查模型名是否正确，或稍后重试。');
        return;
      }
      cb.onDone(content);
    } catch (err) {
      if (!this.cancelled) {
        cb.onError(AiService.networkError(err as BusinessError));
      }
    } finally {
      this.current = null;
      try {
        req.destroy();
      } catch (e) {
        // 忽略销毁失败
      }
    }
  }

  // ---------------- 连接测试 ----------------

  /** 用当前输入框配置测试连接，成功返回模型回复文本，失败抛出带中文说明的异常 */
  static async test(cfg: AiConfig): Promise<string> {
    if (cfg.apiKey.trim().length === 0) {
      throw new Error('请先填写 API Key');
    }
    if (cfg.baseUrl.trim().length === 0) {
      throw new Error('请填写 Base URL');
    }
    if (cfg.model.trim().length === 0) {
      throw new Error('请填写模型名');
    }
    let req: http.HttpRequest = http.createHttp();
    try {
      let messages: ChatMessage[] = [
        { role: 'system', content: '你是连接测试助手。' },
        { role: 'user', content: '请只回复四个字：连接成功' }
      ];
      let body: ChatRequestBody = {
        model: cfg.model.trim(),
        messages: messages,
        stream: false,
        temperature: 0.1,
        max_tokens: 32
      };
      let header: Record<string, string> = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${cfg.apiKey.trim()}`
      };
      let opts: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: header,
        extraData: JSON.stringify(body),
        connectTimeout: Constants.AI_CONNECT_TIMEOUT,
        readTimeout: 20000
      };
      let resp: http.HttpResponse = await req.request(AiService.endpoint(cfg), opts);
      let text: string = AiService.resultText(resp.result);
      if (resp.responseCode !== 200) {
        throw new Error(AiService.statusMessage(resp.responseCode, text));
      }
      let content: string = AiService.parsePlainContent(text);
      if (content.length === 0) {
        let bizError: string = AiService.errorMessageIfAny(text);
        if (bizError.length > 0) {
          throw new Error(bizError);
        }
      }
      return content.length > 0 ? content : '连接成功（模型无文本返回）';
    } finally {
      try {
        req.destroy();
      } catch (e) {
        // 忽略销毁失败
      }
    }
  }

  // ---------------- 工具方法 ----------------

  private static endpoint(cfg: AiConfig): string {
    let base: string = cfg.baseUrl.trim();
    while (base.length > 0 && base.charAt(base.length - 1) === '/') {
      base = base.substring(0, base.length - 1);
    }
    if (base.endsWith('/chat/completions')) {
      return base;
    }
    return `${base}/chat/completions`;
  }

  private static options(cfg: AiConfig, messages: ChatMessage[], stream: boolean): http.HttpRequestOptions {
    let header: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': stream ? 'text/event-stream' : 'application/json',
      'Authorization': `Bearer ${cfg.apiKey.trim()}`
    };
    let body: ChatRequestBody = {
      model: cfg.model.trim(),
      messages: messages,
      stream: stream,
      temperature: cfg.temperature,
      max_tokens: Constants.AI_MAX_TOKENS
    };
    let opts: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: header,
      extraData: JSON.stringify(body),
      connectTimeout: Constants.AI_CONNECT_TIMEOUT,
      readTimeout: Constants.AI_READ_TIMEOUT
    };
    return opts;
  }

  /** 流式分片：choices[0].delta.content */
  private static extractDelta(root: Record<string, Object>): string {
    let choicesValue: Object | undefined = root['choices'];
    if (choicesValue === undefined || choicesValue === null || !Array.isArray(choicesValue)) {
      return '';
    }
    let choices: Object[] = choicesValue as Object[];
    if (choices.length === 0) {
      return '';
    }
    let first: Record<string, Object> = choices[0] as Record<string, Object>;
    let deltaValue: Object | undefined = first['delta'];
    if (deltaValue === undefined || deltaValue === null) {
      return '';
    }
    let delta: Record<string, Object> = deltaValue as Record<string, Object>;
    let content: Object | undefined = delta['content'];
    return typeof content === 'string' ? content as string : '';
  }

  /** 非流式响应：choices[0].message.content（兼容 text 字段） */
  private static extractMessageContent(root: Record<string, Object>): string {
    let choicesValue: Object | undefined = root['choices'];
    if (choicesValue === undefined || choicesValue === null || !Array.isArray(choicesValue)) {
      return '';
    }
    let choices: Object[] = choicesValue as Object[];
    if (choices.length === 0) {
      return '';
    }
    let first: Record<string, Object> = choices[0] as Record<string, Object>;
    let messageValue: Object | undefined = first['message'];
    if (messageValue !== undefined && messageValue !== null) {
      let message: Record<string, Object> = messageValue as Record<string, Object>;
      let content: Object | undefined = message['content'];
      if (typeof content === 'string') {
        return content as string;
      }
    }
    let textValue: Object | undefined = first['text'];
    return typeof textValue === 'string' ? textValue as string : '';
  }

  private static parsePlainContent(text: string): string {
    let t: string = text.trim();
    if (t.length === 0) {
      return '';
    }
    try {
      let root: Record<string, Object> = JSON.parse(t) as Record<string, Object>;
      return AiService.extractMessageContent(root);
    } catch (e) {
      return '';
    }
  }

  /** HTTP 200 但返回业务错误（{"error":...}）时提取错误说明 */
  private static errorMessageIfAny(text: string): string {
    let t: string = text.trim();
    if (t.length === 0) {
      return '';
    }
    try {
      let root: Record<string, Object> = JSON.parse(t) as Record<string, Object>;
      let errValue: Object | undefined = root['error'];
      if (errValue !== undefined && errValue !== null) {
        return AiService.extractErrorMessage(t);
      }
    } catch (e) {
      // 非 JSON，忽略
    }
    return '';
  }

  private static resultText(result: string | Object | ArrayBuffer): string {
    if (typeof result === 'string') {
      return result as string;
    }
    if (result instanceof ArrayBuffer) {
      try {
        let decodeOptions: util.DecodeToStringOptions = { stream: false };
        let decoderOptions: util.TextDecoderOptions = { fatal: false, ignoreBOM: true };
        return util.TextDecoder.create('utf-8', decoderOptions)
          .decodeToString(new Uint8Array(result as ArrayBuffer), decodeOptions);
      } catch (e) {
        return '';
      }
    }
    try {
      return JSON.stringify(result);
    } catch (e) {
      return '';
    }
  }

  private static extractErrorMessage(text: string): string {
    try {
      let root: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
      let errValue: Object | undefined = root['error'];
      if (errValue !== undefined && errValue !== null) {
        if (typeof errValue === 'string') {
          return errValue as string;
        }
        let err: Record<string, Object> = errValue as Record<string, Object>;
        let msgValue: Object | undefined = err['message'];
        if (typeof msgValue === 'string') {
          return msgValue as string;
        }
      }
      let msg: Object | undefined = root['message'];
      if (typeof msg === 'string') {
        return msg as string;
      }
    } catch (e) {
      // 非 JSON 错误体，直接截取原文
    }
    return text.length > 160 ? text.substring(0, 160) : text;
  }

  private static statusMessage(code: number, body: string): string {
    let detail: string = body.trim().length > 0 ? `：${AiService.extractErrorMessage(body)}` : '';
    if (code === 401 || code === 403) {
      return `API Key 无效或无权限（${code}），请到设置中检查${detail}`;
    }
    if (code === 404) {
      return `接口地址或模型名不存在（404），请检查 Base URL 与模型名${detail}`;
    }
    if (code === 429) {
      return `免费模型请求过于频繁或额度已用完（429），请稍后再试${detail}`;
    }
    if (code >= 500) {
      return `模型服务暂时不可用（${code}），请稍后重试${detail}`;
    }
    return `请求失败（${code}）${detail}`;
  }

  private static networkError(err: BusinessError): string {
    let msg: string = err.message !== undefined && err.message !== null ? err.message : `${err}`;
    let low: string = msg.toLowerCase();
    if (low.indexOf('timeout') >= 0) {
      return '请求超时，请检查手机网络后重试。';
    }
    if (low.indexOf('resolve') >= 0 || low.indexOf('dns') >= 0) {
      return '无法解析服务器地址，请检查网络或 Base URL。';
    }
    return `网络请求失败：${msg}`;
  }
}
