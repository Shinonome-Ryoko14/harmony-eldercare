/**
 * 通用数据类型定义
 */

/** 硬件 UDP 上报的原始数值报文（旧协议，仅 UDP 拆分时使用） */
export interface RawDeviceMessage {
  temp?: number;
  humi?: number;
  magnet?: number;
  pulse?: number;
  total?: number;
  sos?: number;
}

/**
 * 解析后的设备实时数据。
 * `ip` 现作为“设备标识”使用（HTTP 模式下取 device_no 的字符串形式），
 * 数据库列名保持 `ip` 不变，避免大范围改动。
 */
export interface DeviceData {
  ip: string;
  deviceNo: number;
  temp: number;
  humi: number;
  /** 门窗磁 door1（0 关 / 1 开） */
  door: number;
  /** 雷达存在（0 无 / 1 有） */
  radarPresence: number;
  /** 雷达运动（0 无 / 1 有） */
  radarMotion: number;
  sos: number;
  /** 设备报警（0 正常 / 1 报警） */
  alarm: number;
  /** 报警类型描述 */
  alarmType: string;
  /** 最后一次收到报文的时间戳(ms) */
  lastSeen: number;
  /** 最后检测到人体活动的时间戳(ms)，0 表示未知 */
  lastActive: number;
  /** 是否在线 */
  online: boolean;
}

/** 接口返回的单条记录（latest 与 history 元素同结构） */
export interface LatestRecord {
  id: number;
  deviceNo: number;
  temp: number;
  humi: number;
  radarPresence: number;
  radarMotion: number;
  door: number;
  sos: number;
  alarm: number;
  alarmType: string;
  /** created_at 解析后的时间戳(ms)，解析失败为 0 */
  ts: number;
}

/** HTTP 拉取状态（用于界面提示） */
export interface FetchState {
  ok: boolean;
  message: string;
  ts: number;
}

/** 告警类型 */
export enum AlertType {
  SOS = 'SOS紧急求助',
  ALARM = '设备报警',
  INACTIVITY = '长时间无活动',
  DOOR_OPEN = '门窗长时间开启',
  TEMP_HIGH = '温度过高',
  TEMP_LOW = '温度过低',
  HUMI_HIGH = '湿度过高',
  HUMI_LOW = '湿度过低',
  OFFLINE = '设备离线'
}

/** 告警级别 */
export enum AlertLevel {
  INFO = 0,
  WARN = 1,
  CRITICAL = 2
}

/** 告警记录 */
export interface AlertRecord {
  id: number;
  ip: string;
  ts: number;
  type: string;
  level: number;
  message: string;
  handled: number;
  handleResult: string;
  handleTs: number;
}

/** 活动记录 */
export interface ActivityRecord {
  id: number;
  ip: string;
  ts: number;
  count: number;
}

/** 居家安全日志（闭环处置记录） */
export interface SafetyLog {
  id: number;
  alertId: number;
  ip: string;
  alertType: string;
  result: string;
  operator: string;
  ts: number;
}

/** 设备信息 */
export interface DeviceInfo {
  ip: string;
  name: string;
  lastSeen: number;
}

/** 单日统计 */
export interface DayStat {
  label: string;
  ts: number;
  count: number;
}

/** 小时分布 */
export interface HourStat {
  hour: number;
  count: number;
}

/** 活动规律报告 */
export interface ReportData {
  today: number;
  yesterday: number;
  diff: number;
  hourly: HourStat[];
}
