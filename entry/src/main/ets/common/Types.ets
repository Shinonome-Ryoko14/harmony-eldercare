/**
 * 通用数据类型定义（HTTP 数据源模式）。
 * 设备统一以 deviceNo（服务端 device_no）作为唯一标识。
 */

/** 解析后的设备实时数据 */
export interface DeviceData {
  /** 设备号（服务端 device_no），设备的唯一标识 */
  deviceNo: number;
  temp: number;
  humi: number;
  /** 门窗磁（APP 内部：1 开 / 0 关；解析时已把硬件 0 开 / 1 关 归一化） */
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
  /** 本地最近一次成功拉取的时间戳(ms)，用于在线判定 */
  lastSeen: number;
  /** 服务端 created_at 时间戳(ms)，用于界面展示 */
  serverTs: number;
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
  DOOR_OPENED = '门窗开启提醒',
  DOOR_OPEN = '门窗长时间开启',
  TEMP_HIGH = '温度过高',
  TEMP_LOW = '温度过低',
  HUMI_HIGH = '湿度过高',
  HUMI_LOW = '湿度过低',
  OFFLINE = '设备离线',
  AWAY = '老人可能外出'
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
  deviceNo: number;
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
  deviceNo: number;
  ts: number;
  count: number;
}

/** 居家安全日志（闭环处置记录） */
export interface SafetyLog {
  id: number;
  alertId: number;
  deviceNo: number;
  alertType: string;
  result: string;
  operator: string;
  ts: number;
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

/** 用户额外添加的门窗（可扩展为其他传感器）配置（旧版扁平结构，仅用于迁移） */
export interface DoorSensorConfig {
  id: string;
  name: string;
  /** 该传感器对应的设备号，APP 会单独轮询这个 device_no */
  deviceNo: number;
}

/** 房间内的单个传感器 */
export interface RoomSensorConfig {
  id: string;
  name: string;
  /** door / window */
  type: string;
  /** 该传感器对应的设备号，APP 会单独轮询这个 device_no */
  deviceNo: number;
}

/** 房间：一个房间可以包含多个门 / 窗传感器 */
export interface RoomConfig {
  id: string;
  name: string;
  sensors: RoomSensorConfig[];
}

