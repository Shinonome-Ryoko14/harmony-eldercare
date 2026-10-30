/**
 * 全局常量配置。服务端字段若变动，只需修改 HTTP_FIELD_ALIASES。
 */
export class Constants {
  /** 超过该时长未成功拉取数据判定离线(ms) */
  static readonly OFFLINE_TIMEOUT: number = 15000;

  /** 无活动告警阈值(ms)，默认 2 小时 */
  static readonly INACTIVITY_THRESHOLD: number = 2 * 60 * 60 * 1000;

  /** 门窗持续开启提醒阈值(ms)，默认 10 分钟 */
  static readonly DOOR_OPEN_THRESHOLD: number = 10 * 60 * 1000;

  /** 门窗动作后，多久内失去人体信号才进入外出判断(ms) */
  static readonly AWAY_DOOR_WINDOW: number = 3 * 60 * 1000;

  /** 连续无人确认外出(ms)，默认 1 分钟 */
  static readonly AWAY_CONFIRM_TIMEOUT: number = 60 * 1000;

  /** 温度上下限(℃) */
  static readonly TEMP_MAX: number = 35;
  static readonly TEMP_MIN: number = 5;

  /** 湿度上下限(%) */
  static readonly HUMI_MAX: number = 90;
  static readonly HUMI_MIN: number = 20;

  // ==================== HTTP 数据源 ====================

  /** 服务器默认地址（可在实时页顶部修改并持久化） */
  static readonly HTTP_DEFAULT_HOST: string = '10.19.81.90';

  /** 服务器默认端口 */
  static readonly HTTP_DEFAULT_PORT: number = 8000;

  /** 默认设备号 */
  static readonly HTTP_DEFAULT_DEVICE_NO: number = 0;

  /** 默认轮询间隔(ms) */
  static readonly HTTP_POLL_INTERVAL: number = 3000;

  /** 连接 / 读取超时(ms) */
  static readonly HTTP_CONNECT_TIMEOUT: number = 5000;
  static readonly HTTP_READ_TIMEOUT: number = 5000;

  /** 接口路径（拼在 http://host:port 之后） */
  static readonly HTTP_API_PATH: string = '/api/device/latest/';

  /** 单次拉取的历史条数 */
  static readonly HTTP_HISTORY_LIMIT: number = 10;

  /**
   * 服务端报文字段候选名（按优先级排列）。
   * 硬件/服务端字段名不一致时，只要把新名字加进对应数组即可，无需改解析代码。
   */
  static readonly HTTP_FIELD_ALIASES: Record<string, string[]> = {
    'id': ['id', 'record_id', 'remote_id', 'seq'],
    'deviceNo': ['device_no', 'deviceNo', 'device_id', 'device'],
    'temp': ['temp', 'temperature', 'Temperature', 'wendu'],
    'humi': ['humi', 'humidity', 'Humidity', 'hum', 'shidu'],
    'radarPresence': ['radar_presence', 'radarPresence', 'presence', 'body', 'human', 'person', 'exist', 'someone'],
    'radarMotion': ['radar_motion', 'radarMotion', 'motion', 'move', 'movement', 'active', 'activity'],
    'door': ['door1', 'door', 'magnet', 'door_status', 'doorState', 'door_open'],
    'sos': ['sos', 'SOS', 'emergency', 'help', 'sos_status'],
    'alarm': ['alarm', 'alarm_status', 'alert', 'warning', 'alarmState'],
    'alarmType': ['alarm_type', 'alarmType', 'alarm_msg', 'alert_type', 'alarm_info'],
    'createdAt': ['created_at', 'createdAt', 'create_time', 'update_time', 'time', 'timestamp', 'ts']
  };

  // ==================== AI 助手 ====================

  /** 默认模型地址（智谱 GLM，OpenAI 兼容；可在设置页修改） */
  static readonly AI_DEFAULT_BASE_URL: string = 'https://open.bigmodel.cn/api/paas/v4';

  /** 默认免费模型（永久免费，仅限并发） */
  static readonly AI_DEFAULT_MODEL: string = 'glm-4-flash';

  /** 默认温度 */
  static readonly AI_DEFAULT_TEMPERATURE: number = 0.5;

  /** 单次回答最大 token 数，控制免费额度消耗 */
  static readonly AI_MAX_TOKENS: number = 800;

  /** 携带的历史对话轮数（消息条数） */
  static readonly AI_HISTORY_TURNS: number = 8;

  /** 连接 / 读取超时(ms)；流式回答可能较慢，读取超时放宽 */
  static readonly AI_CONNECT_TIMEOUT: number = 15000;
  static readonly AI_READ_TIMEOUT: number = 90000;

  /** 流式回答的整体看门狗超时(ms) */
  static readonly AI_STREAM_TIMEOUT: number = 120000;

  /** 两次提问之间的最小间隔(ms)，避免免费模型 429 */
  static readonly AI_MIN_INTERVAL: number = 1500;

  /** 生成提示词时携带的告警条数 */
  static readonly AI_CONTEXT_ALERT_LIMIT: number = 8;

  /** 数据库里最多保留的 AI 消息条数（超出不主动清理，仅限制加载） */
  static readonly AI_HISTORY_LOAD: number = 40;

  /** AI 系统提示词：限定角色、数据依据与安全边界 */
  static readonly AI_SYSTEM_PROMPT: string =
    '你是「居家守护」APP 的 AI 管家，服务对象是独居老人的家属和照护者。请遵守以下规则：\n' +
    '1. 只依据对话中提供的业务数据回答，数据不足时明确说明，绝不编造传感器读数或时间。\n' +
    '2. 使用简体中文，语气温和、具体、可执行；一般不超过 300 字，可用短段落或编号步骤。\n' +
    '3. 不做医学诊断，不推荐处方药；涉及身体不适时建议联系家属或及时就医。\n' +
    '4. 遇到 SOS 求助、设备报警、长时间无活动、设备离线等情况，优先提示立即电话联系老人，必要时拨打 120 或上门查看。\n' +
    '5. 不回答与居家照护无关的内容，礼貌地把话题拉回老人看护。';

  // ==================== USB 串口（CH340） ====================

  /** 默认波特率 */
  static readonly SERIAL_DEFAULT_BAUD: number = 115200;

  /** 串口控制台最多保留的日志行数 */
  static readonly SERIAL_LOG_MAX: number = 300;

  /** CH340 常见 VID（沁恒） */
  static readonly CH340_VENDOR_ID: number = 0x1A86;

  /** 串口单次读取缓冲区大小 */
  static readonly SERIAL_READ_BUFFER: number = 128;
}
