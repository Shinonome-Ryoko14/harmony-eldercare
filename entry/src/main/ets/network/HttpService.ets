import http from '@ohos.net.http';
import { BusinessError } from '@kit.BasicServicesKit';
import { Constants } from '../common/Constants';
import { DateUtil, Protocol } from '../common/Protocol';
import { DeviceData, FetchState, LatestRecord } from '../common/Types';
import { AppStore } from '../store/AppStore';
import { ConfigStore } from '../store/ConfigStore';
import { RdbHelper } from '../data/RdbHelper';
import { Repository } from '../data/Repository';
import { RuleEngine, RuleResult, AlertDraft } from '../data/RuleEngine';

/**
 * HTTP 数据服务：
 * 1) 周期性 GET {base}/api/device/latest/?device_no=X&limit=N
 * 2) 解析 latest + history，按 id 去重
 * 3) **先刷新界面（AppStore），再写数据库**：数据库异常不再影响实时展示
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
    let url: string = ConfigStore.apiUrl(Constants.HTTP_HISTORY_LIMIT);
    let req: http.HttpRequest = http.createHttp();
    try {
      let header: Record<string, string> = { 'Content-Type': 'application/json' };
      let options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: header,
        connectTimeout: Constants.HTTP_CONNECT_TIMEOUT,
        readTimeout: Constants.HTTP_READ_TIMEOUT
      };
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

      let root: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
      let payload: Record<string, Object> = HttpService.unwrap(root);
      let code: number = Protocol.numOf(root, 'code', -1);
      if (code === -1) {
        code = Protocol.numOf(payload, 'code', 0);
      }
      if (code !== 0) {
        this.setState(false, `业务码 ${code}`);
        return;
      }

      let list: LatestRecord[] = HttpService.collect(payload, deviceNo);
      if (list.length === 0) {
        this.setState(true, '已连接（暂无数据）');
        return;
      }

      // ---- 历史展示：最新的在前 ----
      let history: LatestRecord[] = [];
      for (let i: number = list.length - 1; i >= 0; i--) {
        history.push(list[i]);
      }
      let latest: LatestRecord = list[list.length - 1];

      // ---- 组织实时展示数据（不依赖数据库是否可用） ----
      let display: DeviceData = HttpService.toDeviceData(latest);
      display.online = true;
      display.lastSeen = Date.now();

      let activeTs: number = 0;
      for (let i: number = 0; i < list.length; i++) {
        let r: LatestRecord = list[i];
        if (r.radarPresence === 1 || r.radarMotion === 1) {
          if (r.ts > activeTs) {
            activeTs = r.ts;
          }
        }
      }
      // 数据库查询内部已捕获异常，最坏返回 0，不会阻塞界面刷新
      let dbActive: number = RdbHelper.isReady() ? await Repository.lastActiveTs(deviceNo) : 0;
      let memActive: number = RuleEngine.get().lastActiveOf(deviceNo);
      let finalActive: number = activeTs;
      if (dbActive > finalActive) {
        finalActive = dbActive;
      }
      if (memActive > finalActive) {
        finalActive = memActive;
      }
      display.lastActive = finalActive;

      let stamp: number = latest.ts;
      let message: string = stamp > 0
        ? `已连接 · ${DateUtil.time(stamp)}`
        : `已连接 · ${DateUtil.time(Date.now())}`;
      let state: FetchState = { ok: true, message: message, ts: Date.now() };
      let raw: string = text.length > 1500 ? text.substring(0, 1500) : text;

      // ---- 关键：先让界面拿到最新数据 ----
      AppStore.get().applySnapshot(display, history, state, raw, url);

      // ---- 再处理数据库（逐条隔离，失败只记日志） ----
      try {
        await this.persistNewRecords(list, deviceNo);
      } catch (e) {
        console.error(`采样处理异常（不影响界面）: ${JSON.stringify(e)}`);
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

  /** 新记录入库并推导活动/告警；任何一步失败都不影响界面 */
  private async persistNewRecords(list: LatestRecord[], deviceNo: number): Promise<void> {
    if (!RdbHelper.isReady()) {
      // 数据库尚未就绪：本轮只刷新界面，下轮再补写入
      return;
    }
    try {
      if (this.cursorDevice !== deviceNo) {
        this.cursorDevice = deviceNo;
        this.maxId = await Repository.maxRemoteId(deviceNo);
      }
    } catch (e) {
      console.error(`读取入库游标失败: ${JSON.stringify(e)}`);
    }

    for (let i: number = 0; i < list.length; i++) {
      let rec: LatestRecord = list[i];
      if (rec.id <= 0 || rec.id <= this.maxId) {
        continue;
      }
      // 服务端时间解析失败时，入库使用本地时间，避免统计落到 1970 年
      let stored: LatestRecord = rec.ts > 0 ? rec : {
        id: rec.id,
        deviceNo: rec.deviceNo,
        temp: rec.temp,
        humi: rec.humi,
        radarPresence: rec.radarPresence,
        radarMotion: rec.radarMotion,
        door: rec.door,
        sos: rec.sos,
        alarm: rec.alarm,
        alarmType: rec.alarmType,
        ts: Date.now()
      };
      try {
        await Repository.addSample(stored);
      } catch (e) {
        console.error(`采样入库失败（id=${rec.id}）: ${JSON.stringify(e)}`);
        // 数据库暂不可用时跳过，下轮轮询会重新尝试
        continue;
      }
      try {
        let data: DeviceData = HttpService.toDeviceData(stored);
        let result: RuleResult = RuleEngine.get().process(data);
        if (result.activityCount > 0) {
          await Repository.addActivity(deviceNo, stored.ts, result.activityCount);
        }
        for (let j: number = 0; j < result.alerts.length; j++) {
          await Repository.addAlert(deviceNo, result.alerts[j], stored.ts);
        }
      } catch (e) {
        console.error(`告警/活动写入失败（id=${rec.id}）: ${JSON.stringify(e)}`);
      }
      this.maxId = rec.id;
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
        try {
          await Repository.addAlert(d.deviceNo, RuleEngine.get().offlineAlert(), now);
        } catch (e) {
          console.error(`离线告警写入失败: ${JSON.stringify(e)}`);
        }
        continue;
      }
      if (d.online) {
        try {
          let periodic: AlertDraft[] = RuleEngine.get().checkPeriodic(d);
          for (let j: number = 0; j < periodic.length; j++) {
            await Repository.addAlert(d.deviceNo, periodic[j], now);
          }
        } catch (e) {
          console.error(`周期告警写入失败: ${JSON.stringify(e)}`);
        }
      }
    }
  }

  private setState(ok: boolean, message: string): void {
    let state: FetchState = { ok: ok, message: message, ts: Date.now() };
    AppStore.get().setFetchState(state);
  }

  /** 兼容 {code, latest, history} 与 {code, data:{latest, history}} 两种结构 */
  private static unwrap(root: Record<string, Object>): Record<string, Object> {
    let keys: string[] = ['data', 'result', 'payload', 'body'];
    for (let i: number = 0; i < keys.length; i++) {
      let v: Object | undefined = root[keys[i]];
      if (v !== undefined && v !== null && typeof v === 'object' && !Array.isArray(v)) {
        let inner: Record<string, Object> = v as Record<string, Object>;
        if (inner['latest'] !== undefined || inner['history'] !== undefined
          || inner['list'] !== undefined || inner['records'] !== undefined) {
          return inner;
        }
      }
    }
    return root;
  }

  /** 合并 latest + history，去重、归一化设备号并按 id 升序 */
  private static collect(obj: Record<string, Object>, deviceNo: number): LatestRecord[] {
    let all: LatestRecord[] = [];
    let latestObj: Object | undefined = Protocol.pick(obj, ['latest', 'last', 'current', 'newest']);
    if (latestObj !== undefined && latestObj !== null) {
      if (Array.isArray(latestObj)) {
        let arr: Object[] = latestObj as Object[];
        for (let i: number = 0; i < arr.length; i++) {
          all.push(Protocol.parseRecord(arr[i] as Record<string, Object>));
        }
      } else if (typeof latestObj === 'object') {
        all.push(Protocol.parseRecord(latestObj as Record<string, Object>));
      }
    }
    let historyObj: Object | undefined = Protocol.pick(obj, ['history', 'list', 'records', 'items', 'data']);
    if (historyObj !== undefined && historyObj !== null && Array.isArray(historyObj)) {
      let arr: Object[] = historyObj as Object[];
      for (let i: number = 0; i < arr.length; i++) {
        all.push(Protocol.parseRecord(arr[i] as Record<string, Object>));
      }
    }
    // 兼容 {"code":0,"data":{单条记录}} 这种结构
    if (all.length === 0) {
      let single: Object | undefined = Protocol.pick(obj, ['data', 'record', 'item']);
      if (single !== undefined && single !== null && typeof single === 'object' && !Array.isArray(single)) {
        all.push(Protocol.parseRecord(single as Record<string, Object>));
      }
    }
    let map: Map<number, LatestRecord> = new Map<number, LatestRecord>();
    for (let i: number = 0; i < all.length; i++) {
      let rec: LatestRecord = all[i];
      rec.deviceNo = deviceNo;
      let key: number = rec.id > 0 ? rec.id : -(i + 1);
      map.set(key, rec);
    }
    let list: LatestRecord[] = [];
    map.forEach((v: LatestRecord): void => {
      list.push(v);
    });
    list.sort((a: LatestRecord, b: LatestRecord): number => {
      if (a.id > 0 && b.id > 0) {
        return a.id - b.id;
      }
      if (a.ts !== b.ts) {
        return a.ts - b.ts;
      }
      return a.id - b.id;
    });
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
