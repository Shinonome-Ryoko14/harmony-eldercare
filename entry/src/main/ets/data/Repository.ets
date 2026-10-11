import { relationalStore } from '@ohos.data.relationalStore';
import { RdbHelper } from './RdbHelper';
import { AlertDraft } from './RuleEngine';
import { ActivityRecord, AlertRecord, DayStat, HourStat, ReportData, SafetyLog } from '../common/Types';
import { DateUtil } from '../common/Protocol';

/**
 * 数据仓库：活动、告警、安全日志的读写与统计聚合。
 */
export class Repository {

  // ---------------- 写入 ----------------

  static async addActivity(ip: string, ts: number, count: number): Promise<void> {
    let bucket: relationalStore.ValuesBucket = { 'ip': ip, 'ts': ts, 'count': count };
    await RdbHelper.get().insert('activity', bucket);
  }

  static async addAlert(ip: string, draft: AlertDraft, ts: number): Promise<number> {
    let bucket: relationalStore.ValuesBucket = {
      'ip': ip,
      'ts': ts,
      'type': draft.type,
      'level': draft.level,
      'message': draft.message,
      'handled': 0,
      'handle_result': '',
      'handle_ts': 0
    };
    return await RdbHelper.get().insert('alerts', bucket);
  }

  /** 处置告警：更新告警状态并写入安全日志 */
  static async handleAlert(alert: AlertRecord, result: string, operator: string): Promise<void> {
    let now: number = Date.now();
    let pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('alerts');
    pred.equalTo('id', alert.id);
    let values: relationalStore.ValuesBucket = {
      'handled': 1,
      'handle_result': result,
      'handle_ts': now
    };
    await RdbHelper.get().update(values, pred);

    let log: relationalStore.ValuesBucket = {
      'alert_id': alert.id,
      'ip': alert.ip,
      'alert_type': alert.type,
      'result': result,
      'operator': operator,
      'ts': now
    };
    await RdbHelper.get().insert('safety_logs', log);
  }

  // ---------------- 查询 ----------------

  static async queryAlerts(ip: string, limit: number): Promise<AlertRecord[]> {
    let pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('alerts');
    if (ip.length > 0) {
      pred.equalTo('ip', ip);
    }
    pred.orderByDesc('ts');
    pred.limitAs(limit);
    let rs: relationalStore.ResultSet = await RdbHelper.get().query(pred);
    let list: AlertRecord[] = [];
    while (rs.goToNextRow()) {
      list.push(this.readAlert(rs));
    }
    rs.close();
    return list;
  }

  static async queryPendingAlerts(): Promise<AlertRecord[]> {
    let pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('alerts');
    pred.equalTo('handled', 0);
    pred.orderByDesc('ts');
    let rs: relationalStore.ResultSet = await RdbHelper.get().query(pred);
    let list: AlertRecord[] = [];
    while (rs.goToNextRow()) {
      list.push(this.readAlert(rs));
    }
    rs.close();
    return list;
  }

  static async queryLogs(limit: number): Promise<SafetyLog[]> {
    let pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('safety_logs');
    pred.orderByDesc('ts');
    pred.limitAs(limit);
    let rs: relationalStore.ResultSet = await RdbHelper.get().query(pred);
    let list: SafetyLog[] = [];
    while (rs.goToNextRow()) {
      list.push({
        id: rs.getLong(rs.getColumnIndex('id')),
        alertId: rs.getLong(rs.getColumnIndex('alert_id')),
        ip: rs.getString(rs.getColumnIndex('ip')),
        alertType: rs.getString(rs.getColumnIndex('alert_type')),
        result: rs.getString(rs.getColumnIndex('result')),
        operator: rs.getString(rs.getColumnIndex('operator')),
        ts: rs.getLong(rs.getColumnIndex('ts'))
      });
    }
    rs.close();
    return list;
  }

  private static readAlert(rs: relationalStore.ResultSet): AlertRecord {
    return {
      id: rs.getLong(rs.getColumnIndex('id')),
      ip: rs.getString(rs.getColumnIndex('ip')),
      ts: rs.getLong(rs.getColumnIndex('ts')),
      type: rs.getString(rs.getColumnIndex('type')),
      level: rs.getLong(rs.getColumnIndex('level')),
      message: rs.getString(rs.getColumnIndex('message')),
      handled: rs.getLong(rs.getColumnIndex('handled')),
      handleResult: rs.getString(rs.getColumnIndex('handle_result')),
      handleTs: rs.getLong(rs.getColumnIndex('handle_ts'))
    };
  }

  private static async queryActivityRange(ip: string, fromTs: number, toTs: number): Promise<ActivityRecord[]> {
    let pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('activity');
    if (ip.length > 0) {
      pred.equalTo('ip', ip);
    }
    pred.greaterThanOrEqualTo('ts', fromTs);
    pred.lessThan('ts', toTs);
    pred.orderByAsc('ts');
    let rs: relationalStore.ResultSet = await RdbHelper.get().query(pred);
    let list: ActivityRecord[] = [];
    while (rs.goToNextRow()) {
      list.push({
        id: rs.getLong(rs.getColumnIndex('id')),
        ip: rs.getString(rs.getColumnIndex('ip')),
        ts: rs.getLong(rs.getColumnIndex('ts')),
        count: rs.getLong(rs.getColumnIndex('count'))
      });
    }
    rs.close();
    return list;
  }

  // ---------------- 统计 ----------------

  /** 今日 / 昨日活动对比 + 今日时段分布 */
  static async report(ip: string): Promise<ReportData> {
    let now: number = Date.now();
    let todayStart: number = DateUtil.startOfDay(now);
    let yesterdayStart: number = todayStart - 86400000;

    let todayRows: ActivityRecord[] = await this.queryActivityRange(ip, todayStart, now + 1000);
    let yesterdayRows: ActivityRecord[] = await this.queryActivityRange(ip, yesterdayStart, todayStart);

    let today: number = 0;
    let hourly: HourStat[] = [];
    for (let h: number = 0; h < 24; h++) {
      hourly.push({ hour: h, count: 0 });
    }
    todayRows.forEach((r: ActivityRecord) => {
      today += r.count;
      let h: number = DateUtil.hour(r.ts);
      hourly[h].count += r.count;
    });

    let yesterday: number = 0;
    yesterdayRows.forEach((r: ActivityRecord) => {
      yesterday += r.count;
    });

    return {
      today: today,
      yesterday: yesterday,
      diff: today - yesterday,
      hourly: hourly
    };
  }

  /** 最近 days 天每日活动量（用于周/月趋势） */
  static async dailyTrend(ip: string, days: number): Promise<DayStat[]> {
    let todayStart: number = DateUtil.startOfDay(Date.now());
    let fromTs: number = todayStart - (days - 1) * 86400000;
    let rows: ActivityRecord[] = await this.queryActivityRange(ip, fromTs, todayStart + 86400000);

    let list: DayStat[] = [];
    let index: Map<string, number> = new Map<string, number>();
    for (let i: number = 0; i < days; i++) {
      let ts: number = fromTs + i * 86400000;
      let label: string = DateUtil.date(ts).substring(5);
      list.push({ label: label, ts: ts, count: 0 });
      index.set(DateUtil.date(ts), i);
    }
    rows.forEach((r: ActivityRecord) => {
      let key: string = DateUtil.date(r.ts);
      let i: number | undefined = index.get(key);
      if (i !== undefined) {
        list[i].count += r.count;
      }
    });
    return list;
  }
}
