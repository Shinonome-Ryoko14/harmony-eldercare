/**
 * AI 助手相关类型。
 * 统一采用 OpenAI 兼容协议（chat/completions），方便在免费平台之间切换。
 */

/** 模型配置 */
export interface AiConfig {
  /** 形如 https://open.bigmodel.cn/api/paas/v4，不带 /chat/completions */
  baseUrl: string;
  model: string;
  apiKey: string;
  /** 是否使用 SSE 流式输出；失败时自动降级为非流式 */
  stream: boolean;
  temperature: number;
}

/** 发给模型的消息（直接作为请求体 messages） */
export interface ChatMessage {
  role: string;
  content: string;
}

/** 界面消息：比 ChatMessage 多出渲染状态 */
export interface UiMessage {
  id: number;
  role: string;
  content: string;
  /** 是否是错误提示气泡 */
  error: boolean;
  /** 是否正在流式输出 */
  streaming: boolean;
  /** 是否展示“写入处置记录”按钮（由告警页跳转而来） */
  adoptable: boolean;
}

/** 流式回调 */
export interface StreamCallbacks {
  onDelta: (text: string) => void;
  onDone: (full: string) => void;
  onError: (message: string) => void;
}

/** 免费模型平台预设 */
export interface AiPreset {
  name: string;
  baseUrl: string;
  model: string;
  hint: string;
}

/** 内置可选平台（均兼容 OpenAI 协议，免费额度以平台控制台为准） */
export const AI_PRESETS: AiPreset[] = [
  {
    name: '智谱 GLM-4-Flash',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    model: 'glm-4-flash',
    hint: '永久免费 · 推荐'
  },
  {
    name: '智谱 GLM-4.7-Flash',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    model: 'glm-4.7-flash',
    hint: '免费 · 能力更强'
  },
  {
    name: '硅基流动 Qwen2.5-7B',
    baseUrl: 'https://api.siliconflow.cn/v1',
    model: 'Qwen/Qwen2.5-7B-Instruct',
    hint: '免费额度 · 备用'
  }
];

/** 从数据库读出的 AI 会话消息 */
export interface AiMessageRecord {
  id: number;
  role: string;
  content: string;
  ts: number;
}
