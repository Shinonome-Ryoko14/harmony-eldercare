import { Constants } from './Constants';
import { DeviceData } from './Types';

/**
 * 报文解析工具。硬件 JSON 形如：
 * {"temp":26.5,"humi":34,"magnet":0,"pulse":0,"total":0,"sos":0}
 * 通过 Constants.FIELD_KEYS 做字段映射，字段变动只改配置。
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

  /**
   * 解析 UDP 文本为设备数据。
   * @param ip 来源 IP
   * @param text 报文内容
   */
  static parse(ip: string, text: string): DeviceData | null {
    let trimmed: string = text.trim();
    if (trimmed.length === 0 || trimmed.charAt(0) !== '{') {
      return null;
    }
    let rec: Record<string, Object>;
    try {
      rec = JSON.parse(trimmed) as Record<string, Object>;
    } catch (e) {
      return null;
    }
    let keys: Record<string, string> = Constants.FIELD_KEYS;
    let now: number = Date.now();
    let data: DeviceData = {
      ip: ip,
      temp: Protocol.numOf(rec, keys['temp'], 0),
      humi: Protocol.numOf(rec, keys['humi'], 0),
      magnet: Protocol.numOf(rec, keys['magnet'], 0),
      pulse: Protocol.numOf(rec, keys['pulse'], 0),
      total: Protocol.numOf(rec, keys['total'], 0),
      sos: Protocol.numOf(rec, keys['sos'], 0),
      lastSeen: now,
      lastActive: 0,
      online: true
    };
    return data;
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
