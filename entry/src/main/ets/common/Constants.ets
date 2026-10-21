/**
 * 全局常量配置。服务端字段若变动，只需修改 HTTP_FIELD_ALIASES。
 */
export class Constants {
  /** 超过该时长未成功拉取数据判定离线(ms) */
  static readonly OFFLINE_TIMEOUT: number = 15000;

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
