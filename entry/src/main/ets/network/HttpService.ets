import http from '@ohos.net.http';
import { BusinessError } from '@kit.BasicServicesKit';
import { Constants } from '../common/Constants';
import { DateUtil, Protocol } from '../common/Protocol';
import { DeviceData, FetchState, LatestRecord } from '../common/Types';
import { AppStore } from '../store/AppStore';
import { ConfigStore } from '../store/ConfigStore';
import { Repository } from '../data/Repository';
import { RuleEngine, RuleResult, AlertDraft } from '../data/RuleEngine';

/**
 * HTTP 数据服务：
 * 1) 周期性 GET {base}/api/device/latest/?device_no=X&limit=N
 * 2) 解析 latest + history，按 id 去重；新记录入 samples 并推导活动/告警
 * 3) 每次成功拉取都刷新 AppStore 中的实时数据，供所有界面展示
 * 4) 定时巡检在线状态，超时判离线并产生告警
 */
export class HttpService {
  private static instance: HttpService | null = null;
  private pollTimer: number = -1;
  private tickTimer: number = -1;
  private started: boolean = false;
  private fetching: boolean = false;
  /** 当前已处理到的最大服务端记录 id */
  private maxId: number = 0;
  /** maxId 对应的 deviceNo，切换设备号时重新初始化 */
  private cursorDevice: number = -99999;

  static get(): HttpService {
    if (HttpService.instance === null) {
      HttpService.instance = new HttpService();
    }
    return HttpService.instance;
  }

  /** 启动轮询 */
  async start(): Promise<void> {
    if (this.started) {
      return;
    }
    this.started = true;
    this.setState(false, '连接中...');
    await this.refresh();
    this.pollTimer = setInterval(() => {
      this.refresh();
    }, ConfigStore.getPollMs());
    this.tickTimer = setInterval(() => {
      this.tick();
    }, 1000);
  }

  /** 配置变更后重启轮询：重置游标并清空旧设备的实时数据 */
  async restart(): Promise<void> {
    this.stop();
    this.maxId = 0;
    this.cursorDevice = -99999;
    AppStore.get().clearDevices();
    await this.start();
  }

  stop(): void {
    if (this.pollTimer !== -1) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
    if (this.tickTimer !== -1) {
      clearInterval(this.tickTimer);
      this.tickTimer = -1;
    }
    this.started = false;
  }

  /** 立即拉取一次（供手动刷新） */
  async refresh(): Promise<void> {
    if (this.fetching) {
      return;
    }
    this.fetching = true;
    let deviceNo: number = ConfigStore.getDeviceNo();
    let req: http.HttpRequest = http.createHttp();
    try {
      let header: Record<string, string> = { 'Content-Type': 'application/json' };
      let options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: header,
        connectTimeout: Constants.HTTP_CONNECT_TIMEOUT,
        readTimeout: Constants.HTTP_READ_TIMEOUT
      };
      let url: string = ConfigStore.apiUrl(Constants.HTTP_HISTORY_LIMIT);
      let resp: http.HttpResponse = await req.request(url, options);
      if (resp.responseCode !== 200) {
        this.setState(false, `服务器返回 ${resp.responseCode}`);
        return;
      }
      let text: string = typeof resp.result === 'string' ? resp.result as string : '';
      if (text.length === 0) {
        this.setState(false, '响应为空');
        return;
      }
      let obj: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
      let code: number = Protocol.numOf(obj, 'code', -1);
      if (code !== 0) {
        this.setState(false, `业务码 ${code}`);
        return;
      }

      let list: LatestRecord[] = HttpService.collect(obj, deviceNo);
      if (list.length === 0) {
        this.setState(true, '已连接（暂无数据）');
        return;
      }

      // ---- 首次处理某设备时，从数据库恢复已处理的最大 id ----
      if (this.cursorDevice !== deviceNo) {
        this.cursorDevice = deviceNo;
        this.maxId = await Repository.maxRemoteId(deviceNo);
      }

      // ---- 仅对新增记录入库并推导活动/告警 ----
      for (let i: number = 0; i < list.length; i++) {
        let rec: LatestRecord = list[i];
        if (rec.id <= this.maxId) {
          continue;
        }
        await Repository.addSample(rec);
        let data: DeviceData = HttpService.toDeviceData(rec);
        let result: RuleResult = RuleEngine.get().process(data);
        if (result.activityCount > 0) {
          await Repository.addActivity(deviceNo, rec.ts, result.activityCount);
        }
        for (let j: number = 0; j < result.alerts.length; j++) {
          await Repository.addAlert(deviceNo, result.alerts[j], rec.ts);
        }
        this.maxId = rec.id;
      }

      // ---- 关键：无论是否有新记录，都用最新一条刷新实时展示 ----
      let latest: LatestRecord = list[list.length - 1];
      let display: DeviceData = HttpService.toDeviceData(latest);
      let memActive: number = RuleEngine.get().lastActiveOf(deviceNo);
      let dbActive: number = await Repository.lastActiveTs(deviceNo);
      display.lastActive = dbActive > memActive ? dbActive : memActive;
      display.online = true;
      display.lastSeen = Date.now();
      AppStore.get().upsert(display);

      // ---- 历史展示：最新的在前 ----
      let history: LatestRecord[] = [];
      for (let i: number = list.length - 1; i >= 0; i--) {
        history.push(list[i]);
      }
      AppStore.get().setHistory(history);

      let stamp: number = latest.ts;
      if (stamp > 0) {
        this.setState(true, `已连接 · ${DateUtil.time(stamp)}`);
      } else {
        this.setState(true, '已连接');
      }
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      let msg: string = err.message !== undefined ? err.message : '未知错误';
      this.setState(false, `请求失败：${msg}`);
    } finally {
      req.destroy();
      this.fetching = false;
    }
  }

  /** 定时巡检：在线判定 + 周期性告警 */
  private async tick(): Promise<void> {
    let now: number = Date.now();
    let devices: DeviceData[] = AppStore.get().getDevices();
    for (let i: number = 0; i < devices.length; i++) {
      let d: DeviceData = devices[i];
      if (d.online && now - d.lastSeen > Constants.OFFLINE_TIMEOUT) {
        AppStore.get().markOffline(d.deviceNo);
        await Repository.addAlert(d.deviceNo, RuleEngine.get().offlineAlert(), now);
        continue;
      }
      if (d.online) {
        let periodic: AlertDraft[] = RuleEngine.get().checkPeriodic(d);
        for (let j: number = 0; j < periodic.length; j++) {
          await Repository.addAlert(d.deviceNo, periodic[j], now);
        }
      }
    }
  }

  private setState(ok: boolean, message: string): void {
    let state: FetchState = { ok: ok, message: message, ts: Date.now() };
    AppStore.get().setFetchState(state);
  }

  /** 合并 latest + history，去重、归一化设备号并按 id 升序 */
  private static collect(obj: Record<string, Object>, deviceNo: number): LatestRecord[] {
    let all: LatestRecord[] = [];
    let lo: Object | undefined = obj['latest'];
    if (lo !== undefined && lo !== null && typeof lo === 'object') {
      all.push(Protocol.parseRecord(lo as Record<string, Object>));
    }
    let ho: Object | undefined = obj['history'];
    if (ho !== undefined && ho !== null && Array.isArray(ho)) {
      let arr: Object[] = ho as Object[];
      for (let i: number = 0; i < arr.length; i++) {
        all.push(Protocol.parseRecord(arr[i] as Record<string, Object>));
      }
    }
    let map: Map<number, LatestRecord> = new Map<number, LatestRecord>();
    for (let i: number = 0; i < all.length; i++) {
      let rec: LatestRecord = all[i];
      rec.deviceNo = deviceNo;
      map.set(rec.id, rec);
    }
    let list: LatestRecord[] = [];
    map.forEach((v: LatestRecord): void => {
      list.push(v);
    });
    list.sort((a: LatestRecord, b: LatestRecord): number => a.id - b.id);
    return list;
  }

  private static toDeviceData(rec: LatestRecord): DeviceData {
    return {
      deviceNo: rec.deviceNo,
      temp: rec.temp,
      humi: rec.humi,
      door: rec.door,
      radarPresence: rec.radarPresence,
      radarMotion: rec.radarMotion,
      sos: rec.sos,
      alarm: rec.alarm,
      alarmType: rec.alarmType,
      lastSeen: Date.now(),
      serverTs: rec.ts,
      lastActive: 0,
      online: true
    };
  }
}
