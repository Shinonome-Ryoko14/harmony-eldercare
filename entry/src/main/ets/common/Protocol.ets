import { Constants } from './Constants';
import { LatestRecord } from './Types';

/**
 * 服务端报文解析工具。单条记录形如：
 * {"id":168,"device_no":0,"temp":25.4,"humi":52.0,"radar_presence":0,
 *  "radar_motion":0,"door1":0,"sos":0,"alarm":0,"alarm_type":"",
 *  "created_at":"2026-10-13 06:27:57"}
 *
 * 解析采用“候选字段名 + 宽松取值”：
 * - 字段名不确定时，用 Constants.HTTP_FIELD_ALIASES 里的候选列表匹配；
 * - 值支持 number / string / boolean / 开-关 / 有人-无人 等写法。
 */
export class Protocol {

  /** 按候选名取第一个有效值（先精确匹配，再忽略大小写匹配） */
  static pick(rec: Record<string, Object>, aliases: string[]): Object | undefined {
    for (let i: number = 0; i < aliases.length; i++) {
      let v: Object | undefined = rec[aliases[i]];
      if (v !== undefined && v !== null) {
        return v;
      }
    }
    let keys: string[] = Object.keys(rec);
    for (let i: number = 0; i < keys.length; i++) {
      let lower: string = keys[i].toLowerCase();
      for (let j: number = 0; j < aliases.length; j++) {
        if (lower === aliases[j].toLowerCase()) {
          let v: Object | undefined = rec[keys[i]];
          if (v !== undefined && v !== null) {
            return v;
          }
        }
      }
    }
    // 再尝试一层嵌套：例如 {"sensor":{"door1":1}}
    for (let i: number = 0; i < keys.length; i++) {
      let outer: Object | undefined = rec[keys[i]];
      if (outer === undefined || outer === null || typeof outer !== 'object' || Array.isArray(outer)) {
        continue;
      }
      let inner: Record<string, Object> = outer as Record<string, Object>;
      for (let j: number = 0; j < aliases.length; j++) {
        let v: Object | undefined = inner[aliases[j]];
        if (v !== undefined && v !== null) {
          return v;
        }
      }
    }
    return undefined;
  }

  /** 把任意值转成数字（解析失败返回 def） */
  static numValue(v: Object | undefined, def: number): number {
    if (v === undefined || v === null) {
      return def;
    }
    if (typeof v === 'number') {
      return v as number;
    }
    if (typeof v === 'boolean') {
      return (v as boolean) ? 1 : 0;
    }
    if (typeof v === 'string') {
      let s: string = (v as string).trim();
      if (s.length === 0) {
        return def;
      }
      let n: number = Number.parseFloat(s);
      if (!Number.isNaN(n)) {
        return n;
      }
      let flag: number = Protocol.flagOfString(s);
      return flag >= 0 ? flag : def;
    }
    if (typeof v === 'object') {
      let r: Record<string, Object> = v as Record<string, Object>;
      let keys: string[] = ['value', 'state', 'status', 'active', 'count', 'total'];
      for (let i: number = 0; i < keys.length; i++) {
        let inner: Object | undefined = r[keys[i]];
        if (inner !== undefined && inner !== null) {
          let n: number = Protocol.numValue(inner, def);
          if (n !== def) {
            return n;
          }
        }
      }
    }
    return def;
  }

  /** 把任意值转成 0/1 状态（解析失败返回 def） */
  static flagValue(v: Object | undefined, def: number): number {
    if (v === undefined || v === null) {
      return def;
    }
    if (typeof v === 'boolean') {
      return (v as boolean) ? 1 : 0;
    }
    if (typeof v === 'number') {
      return (v as number) !== 0 ? 1 : 0;
    }
    if (typeof v === 'string') {
      let s: string = (v as string).trim();
      if (s.length === 0) {
        return def;
      }
      let n: number = Number.parseFloat(s);
      if (!Number.isNaN(n)) {
        return n !== 0 ? 1 : 0;
      }
      let flag: number = Protocol.flagOfString(s);
      return flag >= 0 ? flag : def;
    }
    if (typeof v === 'object') {
      let r: Record<string, Object> = v as Record<string, Object>;
      let keys: string[] = ['value', 'state', 'status', 'active'];
      for (let i: number = 0; i < keys.length; i++) {
        let inner: Object | undefined = r[keys[i]];
        if (inner !== undefined && inner !== null) {
          return Protocol.flagValue(inner, def);
        }
      }
    }
    return def;
  }

  /** 文本型 0/1：支持 true/false、开/关、有人/无人、报警/正常等 */
  private static flagOfString(s: string): number {
    let low: string = s.toLowerCase();
    if (low === 'true' || low === 'on' || low === 'open' || low === 'opened'
      || low === 'yes' || low === 'active' || low === 'alarm' || low === 'online') {
      return 1;
    }
    if (low === 'false' || low === 'off' || low === 'close' || low === 'closed'
      || low === 'no' || low === 'inactive' || low === 'normal' || low === 'none') {
      return 0;
    }
    // 中文状态：先判断“无/关/正常”，再判断“有/开/报警”
    if (s.indexOf('无') >= 0 || s.indexOf('关') >= 0 || s.indexOf('正常') >= 0
      || s.indexOf('未') >= 0 || s.indexOf('否') >= 0) {
      return 0;
    }
    if (s.indexOf('有') >= 0 || s.indexOf('开') >= 0 || s.indexOf('报警') >= 0
      || s.indexOf('求助') >= 0 || s.indexOf('触发') >= 0 || s.indexOf('是') >= 0) {
      return 1;
    }
    return -1;
  }

  /** 按候选名取数字 */
  static numOfAny(rec: Record<string, Object>, aliases: string[], def: number): number {
    return Protocol.numValue(Protocol.pick(rec, aliases), def);
  }

  /** 按候选名取状态 0/1 */
  static flagOfAny(rec: Record<string, Object>, aliases: string[], def: number): number {
    return Protocol.flagValue(Protocol.pick(rec, aliases), def);
  }

  /**
   * 门窗磁状态归一化。
   * 硬件口径：0 = 开，1 = 关；APP 内部统一为 1 = 开，0 = 关。
   * 文本型仍按 open / closed 的真实语义处理，避免二次反转。
   */
  private static doorValue(v: Object | undefined): number {
    if (v === undefined || v === null) {
      return 0;
    }
    if (typeof v === 'number') {
      return (v as number) !== 0 ? 0 : 1;
    }
    if (typeof v === 'boolean') {
      return (v as boolean) ? 0 : 1;
    }
    if (typeof v === 'string') {
      let s: string = (v as string).trim();
      if (s.length === 0) {
        return 0;
      }
      let n: number = Number.parseFloat(s);
      if (!Number.isNaN(n)) {
        return n !== 0 ? 0 : 1;
      }
      let low: string = s.toLowerCase();
      if (low === 'open' || low === 'opened' || low === 'on' || low === 'true') {
        return 1;
      }
      if (low === 'close' || low === 'closed' || low === 'off' || low === 'false') {
        return 0;
      }
      if (s.indexOf('开') >= 0) {
        return 1;
      }
      if (s.indexOf('关') >= 0) {
        return 0;
      }
      return 0;
    }
    if (typeof v === 'object') {
      let r: Record<string, Object> = v as Record<string, Object>;
      let keys: string[] = ['value', 'state', 'status', 'active'];
      for (let i: number = 0; i < keys.length; i++) {
        let inner: Object | undefined = r[keys[i]];
        if (inner !== undefined && inner !== null) {
          return Protocol.doorValue(inner);
        }
      }
    }
    return 0;
  }

  /** 按候选名取字符串 */
  static strOfAny(rec: Record<string, Object>, aliases: string[], def: string): string {
    let v: Object | undefined = Protocol.pick(rec, aliases);
    if (v === undefined || v === null) {
      return def;
    }
    if (typeof v === 'string') {
      return v as string;
    }
    if (typeof v === 'number') {
      return `${v as number}`;
    }
    if (typeof v === 'boolean') {
      return (v as boolean) ? '1' : '0';
    }
    if (typeof v === 'object') {
      try {
        return JSON.stringify(v);
      } catch (e) {
        return def;
      }
    }
    return def;
  }

  /** 从 Record 中安全读取数值（兼容旧调用） */
  static numOf(rec: Record<string, Object>, key: string, def: number): number {
    return Protocol.numValue(rec[key], def);
  }

  /** 从 Record 中安全读取字符串（兼容旧调用） */
  static strOf(rec: Record<string, Object>, key: string, def: string): string {
    if (key.length === 0) {
      return def;
    }
    return Protocol.strOfAny(rec, [key], def);
  }

  /** 解析服务端单条记录（latest 或 history 元素） */
  static parseRecord(rec: Record<string, Object>): LatestRecord {
    let a: Record<string, string[]> = Constants.HTTP_FIELD_ALIASES;
    let presence: number = Protocol.flagOfAny(rec, a['radarPresence'], 0);
    let motion: number = Protocol.flagOfAny(rec, a['radarMotion'], 0);
    let alarmType: string = Protocol.strOfAny(rec, a['alarmType'], '');
    let alarm: number = Protocol.flagOfAny(rec, a['alarm'], 0);

    // 兼容早期 UDP 硬件字段：只有 pulse/total，没有 radar_presence/radar_motion
    let hasPresence: boolean = Protocol.pick(rec, a['radarPresence']) !== undefined;
    let hasMotion: boolean = Protocol.pick(rec, a['radarMotion']) !== undefined;
    if (!hasMotion) {
      let pulse: number = Protocol.flagOfAny(rec, ['pulse', 'pulses', 'pir'], 0);
      if (pulse > 0) {
        motion = 1;
      }
    }
    if (!hasPresence && motion === 1) {
      presence = 1;
    }
    // 兼容只上报 alarm_type、不上报 alarm 标志的服务端
    if (Protocol.pick(rec, a['alarm']) === undefined && alarmType.length > 0
      && alarmType !== '无' && alarmType !== '0' && alarmType !== 'normal'
      && alarmType !== '正常' && alarmType !== 'none' && alarmType !== 'off') {
      alarm = 1;
    }

    return {
      id: Protocol.numOfAny(rec, a['id'], 0),
      deviceNo: Protocol.numOfAny(rec, a['deviceNo'], 0),
      temp: Protocol.numOfAny(rec, a['temp'], 0),
      humi: Protocol.numOfAny(rec, a['humi'], 0),
      radarPresence: presence,
      radarMotion: motion,
      door: Protocol.doorValue(Protocol.pick(rec, a['door'])),
      sos: Protocol.flagOfAny(rec, a['sos'], 0),
      alarm: alarm,
      alarmType: alarmType,
      ts: Protocol.toTimestamp(Protocol.pick(rec, a['createdAt']))
    };
  }

  /** 任意时间值 -> 毫秒时间戳（失败返回 0） */
  static toTimestamp(v: Object | undefined): number {
    if (v === undefined || v === null) {
      return 0;
    }
    if (typeof v === 'number') {
      return Protocol.normalizeEpoch(v as number);
    }
    if (typeof v === 'string') {
      let s: string = (v as string).trim();
      if (s.length === 0) {
        return 0;
      }
      if (Protocol.isDigits(s)) {
        return Protocol.normalizeEpoch(Number.parseFloat(s));
      }
      return Protocol.parseDateTime(s);
    }
    return 0;
  }

  private static isDigits(s: string): boolean {
    if (s.length === 0) {
      return false;
    }
    for (let i: number = 0; i < s.length; i++) {
      let c: string = s.charAt(i);
      if (c < '0' || c > '9') {
        return false;
      }
    }
    return true;
  }

  /** 秒 / 毫秒 / 微秒时间戳统一成毫秒 */
  private static normalizeEpoch(n: number): number {
    if (n <= 0) {
      return 0;
    }
    if (n > 100000000000000) {
      return Math.floor(n / 1000);
    }
    if (n < 100000000000) {
      return Math.floor(n * 1000);
    }
    return Math.floor(n);
  }

  /**
   * 解析时间字符串为毫秒时间戳。
   * 支持 "2026-10-13 06:27:57"、ISO 8601（含 T/Z/时区）、"2026/10/13 06:27:57"、
   * 只有日期等写法；失败返回 0。
   */
  static parseDateTime(s: string): number {
    let t: string = s.trim();
    if (t.length === 0) {
      return 0;
    }
    // ISO 8601 交给引擎解析（带 T、时区、毫秒）
    if (t.indexOf('T') > 0) {
      let iso: number = Date.parse(t);
      if (!Number.isNaN(iso) && iso > 0) {
        return iso;
      }
    }
    t = t.replace('T', ' ');
    let datePart: string = t;
    let timePart: string = '';
    let space: number = t.indexOf(' ');
    if (space > 0) {
      datePart = t.substring(0, space);
      timePart = t.substring(space + 1).trim();
    }
    datePart = datePart.split('/').join('-');
    let dp: string[] = datePart.split('-');
    if (dp.length < 3) {
      let fallback: number = Date.parse(t);
      return Number.isNaN(fallback) ? 0 : fallback;
    }
    let year: number = Number.parseInt(dp[0]);
    let month: number = Number.parseInt(dp[1]);
    let day: number = Number.parseInt(dp[2]);
    let hour: number = 0;
    let min: number = 0;
    let sec: number = 0;
    if (timePart.length >= 5) {
      let tp: string[] = timePart.split(':');
      if (tp.length >= 2) {
        hour = Number.parseInt(tp[0]);
        min = Number.parseInt(tp[1]);
        if (tp.length >= 3) {
          sec = Number.parseInt(tp[2]);
        }
      }
    }
    if (Number.isNaN(year) || Number.isNaN(month) || Number.isNaN(day)
      || Number.isNaN(hour) || Number.isNaN(min) || Number.isNaN(sec)) {
      return 0;
    }
    if (month < 1 || month > 12 || day < 1 || day > 31
      || hour < 0 || hour > 23 || min < 0 || min > 59 || sec < 0 || sec > 59) {
      return 0;
    }
    let d: Date = new Date(year, month - 1, day, hour, min, sec);
    return d.getTime();
  }
}

/** 时间格式化工具 */
export class DateUtil {
  private static pad(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
  }

  static time(ts: number): string {
    if (ts <= 0) {
      return '--:--:--';
    }
    let d: Date = new Date(ts);
    return `${DateUtil.pad(d.getHours())}:${DateUtil.pad(d.getMinutes())}:${DateUtil.pad(d.getSeconds())}`;
  }

  static dateTime(ts: number): string {
    if (ts <= 0) {
      return '时间未知';
    }
    let d: Date = new Date(ts);
    return `${d.getFullYear()}-${DateUtil.pad(d.getMonth() + 1)}-${DateUtil.pad(d.getDate())} ` +
      `${DateUtil.pad(d.getHours())}:${DateUtil.pad(d.getMinutes())}:${DateUtil.pad(d.getSeconds())}`;
  }

  static date(ts: number): string {
    if (ts <= 0) {
      return '时间未知';
    }
    let d: Date = new Date(ts);
    return `${d.getFullYear()}-${DateUtil.pad(d.getMonth() + 1)}-${DateUtil.pad(d.getDate())}`;
  }

  /** 当天 0 点时间戳 */
  static startOfDay(ts: number): number {
    let d: Date = new Date(ts);
    d.setHours(0, 0, 0, 0);
    return d.getTime();
  }

  static hour(ts: number): number {
    return new Date(ts).getHours();
  }

  /** 相对时间描述 */
  static relative(ts: number): string {
    if (ts <= 0) {
      return '暂无记录';
    }
    let diff: number = Date.now() - ts;
    if (diff < 60000) {
      return '刚刚';
    }
    if (diff < 3600000) {
      return `${Math.floor(diff / 60000)} 分钟前`;
    }
    if (diff < 86400000) {
      return `${Math.floor(diff / 3600000)} 小时前`;
    }
    return `${Math.floor(diff / 86400000)} 天前`;
  }
}
