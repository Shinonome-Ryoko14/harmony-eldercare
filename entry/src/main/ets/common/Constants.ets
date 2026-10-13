/**
 * 全局常量配置。协议字段若变动，只需修改 FIELD_KEYS。
 */
export class Constants {
  /** 硬件通信端口 */
  static readonly UDP_PORT: number = 8888;

  /** APP 发出的探测包内容（硬件收到后回发数据） */
  static readonly PROBE_PACKET: string = 'ELDER_CARE_DISCOVER';

  /** 广播地址（用于发现局域网内设备） */
  static readonly BROADCAST_ADDR: string = '255.255.255.255';

  /** 本机绑定地址 */
  static readonly BIND_ADDR: string = '0.0.0.0';

  /** 探测/扫描间隔(ms) */
  static readonly PROBE_INTERVAL: number = 3000;

  /** 超过该时长未收到报文判定离线(ms) */
  static readonly OFFLINE_TIMEOUT: number = 10000;

  /** 无活动告警阈值(ms)，默认 2 小时 */
  static readonly INACTIVITY_THRESHOLD: number = 2 * 60 * 60 * 1000;

  /** 门窗持续开启告警阈值(ms)，默认 10 分钟 */
  static readonly DOOR_OPEN_THRESHOLD: number = 10 * 60 * 1000;

  /** 温度上下限(℃) */
  static readonly TEMP_MAX: number = 35;
  static readonly TEMP_MIN: number = 5;

  /** 湿度上下限(%) */
  static readonly HUMI_MAX: number = 90;
  static readonly HUMI_MIN: number = 20;

  /** 上报字段名映射（旧 UDP 字段变更时修改此处） */
  static readonly FIELD_KEYS: Record<string, string> = {
    'temp': 'temp',
    'humi': 'humi',
    'magnet': 'magnet',
    'pulse': 'pulse',
    'total': 'total',
    'sos': 'sos'
  };

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

  /** HTTP 报文字段名映射（服务端字段变更时修改此处） */
  static readonly HTTP_FIELDS: Record<string, string> = {
    'id': 'id',
    'deviceNo': 'device_no',
    'temp': 'temp',
    'humi': 'humi',
    'radarPresence': 'radar_presence',
    'radarMotion': 'radar_motion',
    'door': 'door1',
    'sos': 'sos',
    'alarm': 'alarm',
    'alarmType': 'alarm_type',
    'createdAt': 'created_at'
  };
}
