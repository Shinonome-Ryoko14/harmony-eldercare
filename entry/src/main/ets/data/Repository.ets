import relationalStore from '@ohos.data.relationalStore';
import { RdbHelper } from './RdbHelper';
import { AlertDraft } from './RuleEngine';
import { ActivityRecord, AlertRecord, DayStat, HourStat, LatestRecord, ReportData, SafetyLog } from '../common/Types';
import { DateUtil } from '../common/Protocol';

/**
 * 数据仓库：活动、告警、安全日志的读写与统计聚合。
 * 所有表统一以 device_no（number）标识设备。
 */
export class Repository {

  // ---------------- 写入 ----------------

  static async addActivity(deviceNo: number, ts: number, count: number): Promise<void> {
    try {
      let bucket: relationalStore.ValuesBucket = { 'device_no': deviceNo, 'ts': ts, 'count': count };
      await RdbHelper.get().insert('activity', bucket);
    } catch (err) {
      console.error(`写入活动记录失败: ${JSON.stringify(err)}`);
      throw err as Error;
    }
  }

  /**
   * 写入一条服务端采样记录（device_no + remote_id 重复时自动忽略）。
   * @returns 实际插入返回的行号；被忽略时为 -1
   */
  static async addSample(rec: LatestRecord): Promise<number> {
    try {
      let bucket: relationalStore.ValuesBucket = {
        'device_no': rec.deviceNo,
        'remote_id': rec.id,
        'ts': rec.ts,
        'temp': rec.temp,
        'humi': rec.humi,
        'radar_presence': rec.radarPresence,
        'radar_motion': rec.radarMotion,
        'door1': rec.door,
        'sos': rec.sos,
        'alarm': rec.alarm,
        'alarm_type': rec.alarmType
      };
      return await RdbHelper.get().insert('samples', bucket,
        relationalStore.ConflictResolution.ON_CONFLICT_IGNORE);
    } catch (err) {
      console.error(`写入采样记录失败: ${JSON.stringify(err)}`);
      throw err as Error;
    }
  }

  /** 已入库的最大服务端记录 id（用于启动时避免重复累计活动） */
  static async maxRemoteId(deviceNo: number): Promise<number> {
    let maxId: number = 0;
    try {
      let pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('samples');
      pred.equalTo('device_no', deviceNo);
      pred.orderByDesc('remote_id');
      pred.limitAs(1);
      let rs: relationalStore.ResultSet = await RdbHelper.get().query(pred);
      if (rs.goToNextRow()) {
        maxId = rs.getLong(rs.getColumnIndex('remote_id'));
      }
      rs.close();
    } catch (err) {
      console.error(`查询采样最大 id 失败: ${JSON.stringify(err)}`);
    }
    return maxId;
  }

  /** 最近一次检测到雷达“存在/运动”的采样时间戳(ms)，无记录返回 0 */
  static async lastActiveTs(deviceNo: number): Promise<number> {
    let ts: number = 0;
    try {
      let pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('samples');
      pred.equalTo('device_no', deviceNo);
      pred.beginWrap()
        .equalTo('radar_presence', 1)
        .or()
        .equalTo('radar_motion', 1)
        .endWrap();
      pred.orderByDesc('ts');
      pred.limitAs(1);
      let rs: relationalStore.ResultSet = await RdbHelper.get().query(pred);
      if (rs.goToNextRow()) {
        ts = rs.getLong(rs.getColumnIndex('ts'));
      }
      rs.close();
    } catch (err) {
      console.error(`查询最近活动时间失败: ${JSON.stringify(err)}`);
    }
    return ts;
  }

  static async addAlert(deviceNo: number, draft: AlertDraft, ts: number): Promise<number> {
    try {
      let bucket: relationalStore.ValuesBucket = {
        'device_no': deviceNo,
        'ts': ts,
        'type': draft.type,
        'level': draft.level,
        'message': draft.message,
        'handled': 0,
        'handle_result': '',
        'handle_ts': 0
      };
      return await RdbHelper.get().insert('alerts', bucket);
    } catch (err) {
      console.error(`写入告警失败: ${JSON.stringify(err)}`);
      throw err as Error;
    }
  }

  /** 处置告警：更新告警状态并写入安全日志 */
  static async handleAlert(alert: AlertRecord, result: string, operator: string): Promise<void> {
    try {
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
        'device_no': alert.deviceNo,
        'alert_type': alert.type,
        'result': result,
        'operator': operator,
        'ts': now
      };
      await RdbHelper.get().insert('safety_logs', log);
    } catch (err) {
      console.error(`处置告警失败: ${JSON.stringify(err)}`);
      throw err as Error;
    }
  }

  // ---------------- 查询 ----------------

  /** deviceNo < 0 表示查询全部设备 */
  static async queryAlerts(deviceNo: number, limit: number): Promise<AlertRecord[]> {
    let list: AlertRecord[] = [];
    try {
      let pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('alerts');
      if (deviceNo >= 0) {
        pred.equalTo('device_no', deviceNo);
      }
      pred.orderByDesc('ts');
      pred.limitAs(limit);
      let rs: relationalStore.ResultSet = await RdbHelper.get().query(pred);
      while (rs.goToNextRow()) {
        list.push(Repository.readAlert(rs));
      }
      rs.close();
    } catch (err) {
      console.error(`查询告警失败: ${JSON.stringify(err)}`);
      throw err as Error;
    }
    return list;
  }

  static async queryLogs(limit: number): Promise<SafetyLog[]> {
    let list: SafetyLog[] = [];
    try {
      let pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('safety_logs');
      pred.orderByDesc('ts');
      pred.limitAs(limit);
      let rs: relationalStore.ResultSet = await RdbHelper.get().query(pred);
      while (rs.goToNextRow()) {
        list.push({
          id: rs.getLong(rs.getColumnIndex('id')),
          alertId: rs.getLong(rs.getColumnIndex('alert_id')),
          deviceNo: rs.getLong(rs.getColumnIndex('device_no')),
          alertType: rs.getString(rs.getColumnIndex('alert_type')),
          result: rs.getString(rs.getColumnIndex('result')),
          operator: rs.getString(rs.getColumnIndex('operator')),
          ts: rs.getLong(rs.getColumnIndex('ts'))
        });
      }
      rs.close();
    } catch (err) {
      console.error(`查询安全日志失败: ${JSON.stringify(err)}`);
      throw err as Error;
    }
    return list;
  }

  private static readAlert(rs: relationalStore.ResultSet): AlertRecord {
    try {
      return {
        id: rs.getLong(rs.getColumnIndex('id')),
        deviceNo: rs.getLong(rs.getColumnIndex('device_no')),
        ts: rs.getLong(rs.getColumnIndex('ts')),
        type: rs.getString(rs.getColumnIndex('type')),
        level: rs.getLong(rs.getColumnIndex('level')),
        message: rs.getString(rs.getColumnIndex('message')),
        handled: rs.getLong(rs.getColumnIndex('handled')),
        handleResult: rs.getString(rs.getColumnIndex('handle_result')),
        handleTs: rs.getLong(rs.getColumnIndex('handle_ts'))
      };
    } catch (err) {
      console.error(`读取告警行失败: ${JSON.stringify(err)}`);
      throw err as Error;
    }
  }

  private static async queryActivityRange(deviceNo: number, fromTs: number, toTs: number): Promise<ActivityRecord[]> {
    let list: ActivityRecord[] = [];
    try {
      let pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('activity');
      if (deviceNo >= 0) {
        pred.equalTo('device_no', deviceNo);
      }
      pred.greaterThanOrEqualTo('ts', fromTs);
      pred.lessThan('ts', toTs);
      pred.orderByAsc('ts');
      let rs: relationalStore.ResultSet = await RdbHelper.get().query(pred);
      while (rs.goToNextRow()) {
        list.push({
          id: rs.getLong(rs.getColumnIndex('id')),
          deviceNo: rs.getLong(rs.getColumnIndex('device_no')),
          ts: rs.getLong(rs.getColumnIndex('ts')),
          count: rs.getLong(rs.getColumnIndex('count'))
        });
      }
      rs.close();
    } catch (err) {
      console.error(`查询活动区间失败: ${JSON.stringify(err)}`);
      throw err as Error;
    }
    return list;
  }

  // ---------------- 统计 ----------------

  /** 今日 / 昨日活动对比 + 今日时段分布 */
  static async report(deviceNo: number): Promise<ReportData> {
    let now: number = Date.now();
    let todayStart: number = DateUtil.startOfDay(now);
    let yesterdayStart: number = todayStart - 86400000;

    let todayRows: ActivityRecord[] = await Repository.queryActivityRange(deviceNo, todayStart, now + 1000);
    let yesterdayRows: ActivityRecord[] = await Repository.queryActivityRange(deviceNo, yesterdayStart, todayStart);

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
  static async dailyTrend(deviceNo: number, days: number): Promise<DayStat[]> {
    let todayStart: number = DateUtil.startOfDay(Date.now());
    let fromTs: number = todayStart - (days - 1) * 86400000;
    let rows: ActivityRecord[] = await Repository.queryActivityRange(deviceNo, fromTs, todayStart + 86400000);

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
