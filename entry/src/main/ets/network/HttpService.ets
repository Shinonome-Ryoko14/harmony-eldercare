import http from '@ohos.net.http';
import { BusinessError } from '@ohos.base';
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
 * 2) 解析 latest + history，按 id 去重后入库（samples）并推导活动/告警
 * 3) 更新 AppStore 供界面展示，并定时巡检在线状态
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
  private maxIdDevice: number = -99999;

  static get(): HttpService {
    if (HttpService.instance === null) {
      HttpService.instance = new HttpService();
    }
    return HttpService.instance;
  }

  isRunning(): boolean {
    return this.started;
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

  /** 配置变更后重启轮询 */
  async restart(): Promise<void> {
    this.stop();
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
    let key: string = `${deviceNo}`;
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
      let text: string = '';
      if (typeof resp.result === 'string') {
        text = resp.result as string;
      }
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

      // ---- 收集 latest + history ----
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
      if (all.length === 0) {
        this.setState(true, '已连接（暂无数据）');
        return;
      }

      // ---- 去重 + 按 id 升序 ----
      let map: Map<number, LatestRecord> = new Map<number, LatestRecord>();
      for (let i: number = 0; i < all.length; i++) {
        map.set(all[i].id, all[i]);
      }
      let list: LatestRecord[] = [];
      map.forEach((v: LatestRecord): void => {
        list.push(v);
      });
      list.sort((a: LatestRecord, b: LatestRecord): number => a.id - b.id);

      // ---- 首次处理某设备时，从数据库恢复已处理的最大 id ----
      if (this.maxIdDevice !== deviceNo) {
        this.maxIdDevice = deviceNo;
        this.maxId = await Repository.maxRemoteId(deviceNo);
      }

      // ---- 仅处理新记录 ----
      let newest: DeviceData | null = null;
      for (let i: number = 0; i < list.length; i++) {
        let rec: LatestRecord = list[i];
        if (rec.id <= this.maxId) {
          continue;
        }
        await Repository.addSample(rec);
        let data: DeviceData = HttpService.toDeviceData(key, rec);
        let result: RuleResult = RuleEngine.get().process(data);
        if (result.activityCount > 0) {
          await Repository.addActivity(key, rec.ts, result.activityCount);
        }
        for (let j: number = 0; j < result.alerts.length; j++) {
          await Repository.addAlert(key, result.alerts[j], rec.ts);
        }
        if (rec.id > this.maxId) {
          this.maxId = rec.id;
        }
        newest = data;
      }

      // ---- 历史展示：最新的在前 ----
      let display: LatestRecord[] = [];
      for (let i: number = list.length - 1; i >= 0; i--) {
        display.push(list[i]);
      }
      AppStore.get().setHistory(display);
      if (newest !== null) {
        newest.online = true;
        AppStore.get().upsert(newest);
      }

      let stamp: number = display[0].ts;
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
        AppStore.get().markOffline(d.ip);
        await Repository.addAlert(d.ip, RuleEngine.get().offlineAlert(), now);
        continue;
      }
      if (d.online) {
        let periodic: AlertDraft[] = RuleEngine.get().checkPeriodic(d);
        for (let j: number = 0; j < periodic.length; j++) {
          await Repository.addAlert(d.ip, periodic[j], now);
        }
      }
    }
  }

  private setState(ok: boolean, message: string): void {
    let state: FetchState = { ok: ok, message: message, ts: Date.now() };
    AppStore.get().setFetchState(state);
  }

  private static toDeviceData(key: string, rec: LatestRecord): DeviceData {
    return {
      ip: key,
      deviceNo: rec.deviceNo,
      temp: rec.temp,
      humi: rec.humi,
      door: rec.door,
      radarPresence: rec.radarPresence,
      radarMotion: rec.radarMotion,
      sos: rec.sos,
      alarm: rec.alarm,
      alarmType: rec.alarmType,
      lastSeen: rec.ts,
      lastActive: 0,
      online: true
    };
  }
}
