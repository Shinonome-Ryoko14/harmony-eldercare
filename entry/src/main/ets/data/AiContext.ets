import { AlertRecord, DayStat, DeviceData, ReportData } from '../common/Types';
import { DateUtil } from '../common/Protocol';
import { Constants } from '../common/Constants';
import { AppStore } from '../store/AppStore';
import { Repository } from './Repository';

/**
 * AI 业务上下文。
 * 把实时数据、活动统计与告警压缩成一段结构化文本：
 * - prompt() 供模型生成回答；
 * - brief() 在未配置 Key / 断网时生成本地模板简报，保证演示不中断。
 */

/** 一次快照：AI 回答所需的全部业务数据 */
export interface CareSnapshot {
  now: number;
  deviceNo: number;
  hasDevice: boolean;
  online: boolean;
  temp: number;
  humi: number;
  door: number;
  presence: number;
  motion: number;
  sos: number;
  alarm: number;
  alarmType: string;
  lastActive: number;
  today: number;
  yesterday: number;
  week: DayStat[];
  alerts: AlertRecord[];
}

export class AiContext {

  static async snapshot(deviceNo: number): Promise<CareSnapshot> {
    let now: number = Date.now();
    let snap: CareSnapshot = {
      now: now,
      deviceNo: deviceNo,
      hasDevice: false,
      online: false,
      temp: 0,
      humi: 0,
      door: 0,
      presence: 0,
      motion: 0,
      sos: 0,
      alarm: 0,
      alarmType: '',
      lastActive: 0,
      today: 0,
      yesterday: 0,
      week: [],
      alerts: []
    };

    let d: DeviceData | undefined = AppStore.get().current();
    if (d !== undefined) {
      snap.hasDevice = true;
      snap.online = d.online;
      snap.temp = d.temp;
      snap.humi = d.humi;
      snap.door = d.door;
      snap.presence = d.radarPresence;
      snap.motion = d.radarMotion;
      snap.sos = d.sos;
      snap.alarm = d.alarm;
      snap.alarmType = d.alarmType;
      snap.lastActive = d.lastActive;
    }

    try {
      let report: ReportData = await Repository.report(deviceNo);
      snap.today = report.today;
      snap.yesterday = report.yesterday;
    } catch (e) {
      console.error(`AI 上下文读取报告失败: ${JSON.stringify(e)}`);
    }

    try {
      snap.week = await Repository.dailyTrend(deviceNo, 7);
    } catch (e) {
      console.error(`AI 上下文读取趋势失败: ${JSON.stringify(e)}`);
    }

    try {
      snap.alerts = await Repository.queryAlerts(deviceNo, Constants.AI_CONTEXT_ALERT_LIMIT);
    } catch (e) {
      console.error(`AI 上下文读取告警失败: ${JSON.stringify(e)}`);
    }

    return snap;
  }

  /** 供模型阅读的结构化上下文 */
  static prompt(s: CareSnapshot): string {
    let lines: string[] = [];
    lines.push(`当前时间：${DateUtil.dateTime(s.now)}`);

    if (s.hasDevice) {
      lines.push(`设备号：${s.deviceNo}，状态：${s.online ? '在线' : '离线（超过 15 秒未成功上报）'}`);
      let tempText: string = s.temp !== 0 ? `${s.temp}℃` : '暂无';
      let humiText: string = s.humi !== 0 ? `${s.humi}%` : '暂无';
      lines.push(`室内环境：温度 ${tempText}，湿度 ${humiText}`);
      lines.push(`门窗磁：${s.door === 1 ? '开启' : '关闭'}；雷达存在：${s.presence === 1 ? '有人' : '无人'}；` +
        `雷达运动：${s.motion === 1 ? '有活动' : '无活动'}`);
      lines.push(`紧急求助：${s.sos === 1 ? '已触发' : '未触发'}；` +
        `设备报警：${s.alarm === 1 ? (s.alarmType.length > 0 ? s.alarmType : '已触发') : '无'}`);
      if (s.lastActive > 0) {
        lines.push(`最后检测到人体活动：${DateUtil.dateTime(s.lastActive)}（${DateUtil.relative(s.lastActive)}）`);
      } else {
        lines.push('最后检测到人体活动：暂无记录');
      }
    } else {
      lines.push('实时数据：暂无（设备尚未上报，请勿臆测任何读数）');
    }

    if (s.today > 0 || s.yesterday > 0) {
      let diff: number = s.today - s.yesterday;
      let trend: string = diff > 0 ? `增加 ${diff} 次` : (diff < 0 ? `减少 ${-diff} 次` : '持平');
      lines.push(`活动统计：今日 ${s.today} 次，昨日 ${s.yesterday} 次，较昨日${trend}`);
    } else {
      lines.push('活动统计：暂无活动记录');
    }

    if (s.week.length > 0) {
      let total: number = 0;
      let items: string[] = [];
      for (let i: number = 0; i < s.week.length; i++) {
        total += s.week[i].count;
        items.push(`${s.week[i].label} ${s.week[i].count}次`);
      }
      let avg: number = total / s.week.length;
      lines.push(`近 ${s.week.length} 天活动：${items.join('，')}`);
      lines.push(`日均活动 ${avg.toFixed(1)} 次`);
    }

    if (s.alerts.length === 0) {
      lines.push('告警记录：最近没有告警');
    } else {
      lines.push('最近告警（新 -> 旧）：');
      for (let i: number = 0; i < s.alerts.length; i++) {
        let a: AlertRecord = s.alerts[i];
        let state: string = a.handled === 1 ? `已处置：${a.handleResult}` : '未处置';
        lines.push(`- ${DateUtil.dateTime(a.ts)} ${a.type}（${state}）：${a.message}`);
      }
    }

    return lines.join('\n');
  }

  /** 给家属的通知草稿：无 Key 时按本地数据生成 */
  static notice(s: CareSnapshot): string {
    let lines: string[] = [];
    lines.push('【给家属的通知】');
    lines.push(`时间：${DateUtil.dateTime(s.now)}`);
    if (s.hasDevice) {
      let tempText: string = s.temp !== 0 ? `${s.temp}℃` : '温度暂无';
      let humiText: string = s.humi !== 0 ? `${s.humi}%` : '湿度暂无';
      lines.push(`今天老人的居家状态：${s.online ? '设备在线' : '设备暂时离线'}，` +
        `室内 ${tempText} / ${humiText}，门窗${s.door === 1 ? '开启' : '关闭'}。`);
    } else {
      lines.push('今天暂未收到设备数据，请检查网关和网络。');
    }
    if (s.today > 0 || s.yesterday > 0) {
      lines.push(`活动情况：今日 ${s.today} 次，昨日 ${s.yesterday} 次。`);
    }
    let pending: number = 0;
    for (let i: number = 0; i < s.alerts.length; i++) {
      if (s.alerts[i].handled === 0) {
        pending = pending + 1;
      }
    }
    lines.push(pending > 0 ? `目前有 ${pending} 条告警待处置，请及时确认。` : '目前没有待处置告警。');
    lines.push('请抽空电话问候，确认进食、睡眠和用药情况；如有身体不适请及时就医。');
    return lines.join('\n');
  }

  /** 本地模板简报：无 Key / 断网时的降级回答 */
  static brief(s: CareSnapshot): string {
    let lines: string[] = [];
    lines.push('【今日照护简报】');
    lines.push(`时间：${DateUtil.dateTime(s.now)}`);

    if (s.hasDevice) {
      let tempText: string = s.temp !== 0 ? `${s.temp}℃` : '温度暂无';
      let humiText: string = s.humi !== 0 ? `${s.humi}%` : '湿度暂无';
      lines.push(`实时状态：${s.online ? '设备在线' : '设备离线'}，` +
        `室内 ${tempText} / ${humiText}，门窗${s.door === 1 ? '开启' : '关闭'}，` +
        `雷达${s.presence === 1 ? '检测到有人' : '未检测到人'}，` +
        `${s.sos === 1 ? '紧急求助已触发' : '无紧急求助'}，` +
        `${s.alarm === 1 ? `设备报警：${s.alarmType.length > 0 ? s.alarmType : '已触发'}` : '无设备报警'}。`);
      if (s.lastActive > 0) {
        lines.push(`最后活动：${DateUtil.dateTime(s.lastActive)}（${DateUtil.relative(s.lastActive)}）。`);
      } else {
        lines.push('最后活动：暂无活动记录。');
      }
    } else {
      lines.push('实时状态：暂未收到设备数据，请先检查网关、WiFi 与上报地址。');
    }

    if (s.today > 0 || s.yesterday > 0) {
      let diff: number = s.today - s.yesterday;
      let trend: string = diff > 0 ? `比昨日多 ${diff} 次` : (diff < 0 ? `比昨日少 ${-diff} 次` : '与昨日持平');
      lines.push(`活动情况：今日 ${s.today} 次，昨日 ${s.yesterday} 次，${trend}。`);
    } else {
      lines.push('活动情况：暂无活动数据。');
    }

    let pending: number = 0;
    for (let i: number = 0; i < s.alerts.length; i++) {
      if (s.alerts[i].handled === 0) {
        pending = pending + 1;
      }
    }
    if (s.alerts.length === 0) {
      lines.push('近期告警：暂无。');
    } else {
      lines.push(`近期告警：共 ${s.alerts.length} 条，其中 ${pending} 条待处置。`);
      let shown: number = s.alerts.length > 3 ? 3 : s.alerts.length;
      for (let i: number = 0; i < shown; i++) {
        let a: AlertRecord = s.alerts[i];
        lines.push(`- ${DateUtil.dateTime(a.ts)} ${a.type}${a.handled === 0 ? '（待处置）' : '（已处置）'}`);
      }
    }

    let tips: string[] = [];
    if (s.sos === 1) {
      tips.push('检测到紧急求助，请立即电话联系老人；无人应答请尽快上门或拨打 120。');
    }
    if (s.alarm === 1) {
      tips.push(`设备报警${s.alarmType.length > 0 ? `（${s.alarmType}）` : ''}，请先确认现场情况，再填写处置结果。`);
    }
    if (!s.hasDevice || !s.online) {
      tips.push('设备当前离线，请检查网关电源、WiFi 与上报地址，必要时重启设备。');
    }
    if (s.door === 1) {
      tips.push('门窗处于开启状态，请确认是正常通风还是忘记关闭。');
    }
    if (s.temp !== 0 && (s.temp > Constants.TEMP_MAX || s.temp < Constants.TEMP_MIN)) {
      tips.push(`室温 ${s.temp}℃ 超出舒适范围，请检查空调、暖气或开窗情况。`);
    }
    if (s.humi !== 0 && (s.humi > Constants.HUMI_MAX || s.humi < Constants.HUMI_MIN)) {
      tips.push(`湿度 ${s.humi}% 超出舒适范围，注意通风或除湿。`);
    }
    if (s.lastActive > 0 && s.now - s.lastActive > Constants.INACTIVITY_THRESHOLD) {
      tips.push(`已有 ${DateUtil.relative(s.lastActive)} 未检测到活动，建议电话问候确认状态。`);
    }
    if (s.yesterday >= 5 && s.today < s.yesterday * 0.6) {
      tips.push('今日活动量明显低于昨日，请关注老人身体与情绪状态。');
    }
    if (tips.length === 0) {
      tips.push('各项指标正常，保持日常关注即可。');
    }

    lines.push('建议：');
    for (let i: number = 0; i < tips.length; i++) {
      lines.push(`${i + 1}. ${tips[i]}`);
    }
    lines.push('（本简报由本地规则生成，未调用大模型）');
    return lines.join('\n');
  }
}
