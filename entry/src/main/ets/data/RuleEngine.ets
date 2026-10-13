import { Constants } from '../common/Constants';
import { AlertLevel, AlertType, DeviceData } from '../common/Types';

/** 待写入数据库的告警草稿 */
export interface AlertDraft {
  type: string;
  level: number;
  message: string;
}

/** 单次报文处理结果 */
export interface RuleResult {
  activityCount: number;
  activeNow: boolean;
  doorOpened: boolean;
  doorClosed: boolean;
  alerts: AlertDraft[];
}

interface RuleState {
  lastPresence: number;
  lastMotion: number;
  lastDoor: number;
  doorOpenSince: number;
  sosActive: boolean;
  alarmActive: boolean;
  inactivityAlerted: boolean;
  doorAlerted: boolean;
  /** 最近一次“有人/有运动”的时间戳(ms) */
  lastActive: number;
  lastAlertTs: Map<string, number>;
}

/**
 * 告警规则引擎：从周期性报文的状态变化中推导活动、门窗事件与告警。
 * 适配 HTTP 新字段：radar_presence / radar_motion / door1 / sos / alarm / alarm_type。
 */
export class RuleEngine {
  private static instance: RuleEngine | null = null;
  private states: Map<string, RuleState> = new Map<string, RuleState>();
  private static readonly COOLDOWN: number = 10 * 60 * 1000;

  static get(): RuleEngine {
    if (RuleEngine.instance === null) {
      RuleEngine.instance = new RuleEngine();
    }
    return RuleEngine.instance;
  }

  private stateOf(ip: string): RuleState {
    let s: RuleState | undefined = this.states.get(ip);
    if (s === undefined) {
      s = {
        lastPresence: -1,
        lastMotion: -1,
        lastDoor: -1,
        doorOpenSince: 0,
        sosActive: false,
        alarmActive: false,
        inactivityAlerted: false,
        doorAlerted: false,
        lastActive: 0,
        lastAlertTs: new Map<string, number>()
      };
      this.states.set(ip, s);
    }
    return s;
  }

  private allowed(s: RuleState, key: string, now: number): boolean {
    let last: number | undefined = s.lastAlertTs.get(key);
    if (last !== undefined && now - last < RuleEngine.COOLDOWN) {
      return false;
    }
    s.lastAlertTs.set(key, now);
    return true;
  }

  /** 处理一条新报文（会就地更新 data.lastActive） */
  process(data: DeviceData): RuleResult {
    let now: number = data.lastSeen > 0 ? data.lastSeen : Date.now();
    let s: RuleState = this.stateOf(data.ip);
    let result: RuleResult = {
      activityCount: 0,
      activeNow: false,
      doorOpened: false,
      doorClosed: false,
      alerts: []
    };
    let moving: boolean = data.radarMotion === 1;
    let present: boolean = data.radarPresence === 1;

    // ---- 活动检测：雷达运动/存在的上升沿记一次活动 ----
    if (moving && s.lastMotion !== 1) {
      result.activityCount += 1;
    } else if (present && s.lastPresence !== 1) {
      result.activityCount += 1;
    }
    if (moving || present) {
      result.activeNow = true;
      s.lastActive = now;
      s.inactivityAlerted = false;
    }
    data.lastActive = s.lastActive;

    // ---- 门窗检测（door1 0→1 开，1→0 关） ----
    if (s.lastDoor === 0 && data.door === 1) {
      result.doorOpened = true;
      s.doorOpenSince = now;
      s.doorAlerted = false;
    } else if (s.lastDoor === 1 && data.door === 0) {
      result.doorClosed = true;
      s.doorOpenSince = 0;
      s.doorAlerted = false;
    }

    // ---- SOS 紧急求助（上升沿触发） ----
    if (data.sos === 1 && !s.sosActive) {
      result.alerts.push({
        type: AlertType.SOS,
        level: AlertLevel.CRITICAL,
        message: '老人触发紧急求助按钮！请立即联系确认。'
      });
      s.sosActive = true;
    } else if (data.sos === 0) {
      s.sosActive = false;
    }

    // ---- 设备报警（上升沿触发） ----
    if (data.alarm === 1 && !s.alarmActive) {
      let typeText: string = data.alarmType.length > 0 ? data.alarmType : '未知类型';
      result.alerts.push({
        type: AlertType.ALARM,
        level: AlertLevel.CRITICAL,
        message: `设备触发报警（${typeText}），请及时确认现场情况。`
      });
      s.alarmActive = true;
    } else if (data.alarm === 0) {
      s.alarmActive = false;
    }

    // ---- 环境异常 ----
    if (data.temp > Constants.TEMP_MAX && this.allowed(s, 'temp', now)) {
      result.alerts.push({
        type: AlertType.TEMP_HIGH,
        level: AlertLevel.WARN,
        message: `室内温度 ${data.temp}℃ 偏高，请注意。`
      });
    } else if (data.temp < Constants.TEMP_MIN && data.temp !== 0 && this.allowed(s, 'temp', now)) {
      result.alerts.push({
        type: AlertType.TEMP_LOW,
        level: AlertLevel.WARN,
        message: `室内温度 ${data.temp}℃ 偏低，请注意保暖。`
      });
    }
    if (data.humi > Constants.HUMI_MAX && this.allowed(s, 'humi', now)) {
      result.alerts.push({
        type: AlertType.HUMI_HIGH,
        level: AlertLevel.WARN,
        message: `室内湿度 ${data.humi}% 偏高，请注意。`
      });
    } else if (data.humi < Constants.HUMI_MIN && data.humi !== 0 && this.allowed(s, 'humi', now)) {
      result.alerts.push({
        type: AlertType.HUMI_LOW,
        level: AlertLevel.WARN,
        message: `室内湿度 ${data.humi}% 偏低，请注意。`
      });
    }

    // 保存状态
    s.lastPresence = data.radarPresence;
    s.lastMotion = data.radarMotion;
    s.lastDoor = data.door;
    return result;
  }

  /** 周期性检查（无活动、门窗久开） */
  checkPeriodic(data: DeviceData): AlertDraft[] {
    let now: number = Date.now();
    let s: RuleState = this.stateOf(data.ip);
    let alerts: AlertDraft[] = [];

    if (data.lastActive > 0 && now - data.lastActive > Constants.INACTIVITY_THRESHOLD
      && !s.inactivityAlerted) {
      alerts.push({
        type: AlertType.INACTIVITY,
        level: AlertLevel.WARN,
        message: `已超过 ${Math.floor(Constants.INACTIVITY_THRESHOLD / 3600000)} 小时未检测到活动，请关注老人状态。`
      });
      s.inactivityAlerted = true;
    }

    if (s.doorOpenSince > 0 && now - s.doorOpenSince > Constants.DOOR_OPEN_THRESHOLD
      && !s.doorAlerted) {
      alerts.push({
        type: AlertType.DOOR_OPEN,
        level: AlertLevel.WARN,
        message: '门窗已持续开启较长时间，请确认是否关好。'
      });
      s.doorAlerted = true;
    }
    return alerts;
  }

  /** 设备离线告警 */
  offlineAlert(): AlertDraft {
    return {
      type: AlertType.OFFLINE,
      level: AlertLevel.WARN,
      message: '设备已离线，请检查网关电源与网络。'
    };
  }
}
