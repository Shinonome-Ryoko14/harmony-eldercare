import { Constants } from './Constants';
import { LatestRecord } from './Types';

/**
 * 服务端报文解析工具。单条记录形如：
 * {"id":168,"device_no":0,"temp":25.4,"humi":52.0,"radar_presence":0,
 *  "radar_motion":0,"door1":0,"sos":0,"alarm":0,"alarm_type":"",
 *  "created_at":"2026-10-13 06:27:57"}
 * 通过 Constants.HTTP_FIELDS 做字段映射，字段变动只改配置。
 */
export class Protocol {

  /** 从 Record 中安全读取数值 */
  static numOf(rec: Record<string, Object>, key: string, def: number): number {
    let v: Object | undefined = rec[key];
    if (v === undefined) {
      return def;
    }
    if (typeof v === 'number') {
      return v as number;
    }
    if (typeof v === 'string') {
      let n: number = Number.parseFloat(v as string);
      if (!Number.isNaN(n)) {
        return n;
      }
    }
    if (typeof v === 'boolean') {
      return (v as boolean) ? 1 : 0;
    }
    return def;
  }

  /** 从 Record 中安全读取字符串 */
  static strOf(rec: Record<string, Object>, key: string, def: string): string {
    if (key.length === 0) {
      return def;
    }
    let v: Object | undefined = rec[key];
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
    return def;
  }

  /** 解析服务端单条记录（latest 或 history 元素） */
  static parseRecord(rec: Record<string, Object>): LatestRecord {
    let f: Record<string, string> = Constants.HTTP_FIELDS;
    let created: string = Protocol.strOf(rec, f['createdAt'], '');
    return {
      id: Protocol.numOf(rec, f['id'], 0),
      deviceNo: Protocol.numOf(rec, f['deviceNo'], 0),
      temp: Protocol.numOf(rec, f['temp'], 0),
      humi: Protocol.numOf(rec, f['humi'], 0),
      radarPresence: Protocol.numOf(rec, f['radarPresence'], 0),
      radarMotion: Protocol.numOf(rec, f['radarMotion'], 0),
      door: Protocol.numOf(rec, f['door'], 0),
      sos: Protocol.numOf(rec, f['sos'], 0),
      alarm: Protocol.numOf(rec, f['alarm'], 0),
      alarmType: Protocol.strOf(rec, f['alarmType'], ''),
      ts: Protocol.parseDateTime(created)
    };
  }

  /**
   * 解析 "2026-10-13 06:27:57"（或 ISO 的 "...T..."）为时间戳(ms)。
   * 服务端返回的是服务器本地时间，与手机本地时区一致，故按本地时间解析。
   * 不用 new Date(str)，避免各引擎对非 ISO 格式解析不一致。
   */
  static parseDateTime(s: string): number {
    if (s.length < 19) {
      return 0;
    }
    let t: string = s.trim();
    if (t.length < 19) {
      return 0;
    }
    t = t.replace('T', ' ');
    let year: number = Number.parseInt(t.substring(0, 4));
    let month: number = Number.parseInt(t.substring(5, 7));
    let day: number = Number.parseInt(t.substring(8, 10));
    let hour: number = Number.parseInt(t.substring(11, 13));
    let min: number = Number.parseInt(t.substring(14, 16));
    let sec: number = Number.parseInt(t.substring(17, 19));
    if (Number.isNaN(year) || Number.isNaN(month) || Number.isNaN(day)
      || Number.isNaN(hour) || Number.isNaN(min) || Number.isNaN(sec)) {
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
    let d: Date = new Date(ts);
    return `${DateUtil.pad(d.getHours())}:${DateUtil.pad(d.getMinutes())}:${DateUtil.pad(d.getSeconds())}`;
  }

  static dateTime(ts: number): string {
    let d: Date = new Date(ts);
    return `${d.getFullYear()}-${DateUtil.pad(d.getMonth() + 1)}-${DateUtil.pad(d.getDate())} ` +
      `${DateUtil.pad(d.getHours())}:${DateUtil.pad(d.getMinutes())}:${DateUtil.pad(d.getSeconds())}`;
  }

  static date(ts: number): string {
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
