/**
 * 通用数据类型定义
 */

/** 硬件 UDP 上报的原始数值报文（字段可能变动） */
export interface RawDeviceMessage {
  temp?: number;
  humi?: number;
  magnet?: number;
  pulse?: number;
  total?: number;
  sos?: number;
}

/** 解析后的设备实时数据 */
export interface DeviceData {
  ip: string;
  temp: number;
  humi: number;
  magnet: number;
  pulse: number;
  total: number;
  sos: number;
  /** 最后一次收到报文的时间戳(ms) */
  lastSeen: number;
  /** 最后检测到人体活动的时间戳(ms)，0 表示未知 */
  lastActive: number;
  /** 是否在线 */
  online: boolean;
}

/** 告警类型 */
export enum AlertType {
  SOS = 'SOS紧急求助',
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
