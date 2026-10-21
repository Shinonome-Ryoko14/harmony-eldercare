import { DeviceData, FetchState, LatestRecord } from '../common/Types';
import { ConfigStore } from './ConfigStore';

export type StoreListener = (devices: DeviceData[]) => void;

/**
 * 全局内存状态：保存各设备的实时数据、最近上报历史与拉取状态，并通知订阅者。
 * 设备以 deviceNo 唯一标识。
 *
 * 说明：每次写入都用“新对象 + 版本号”的方式更新，避免 ArkUI 因引用未变而漏掉重绘。
 */
export class AppStore {
  private static instance: AppStore | null = null;
  private devices: Map<number, DeviceData> = new Map<number, DeviceData>();
  private selectedDeviceNo: number = -1;
  private listeners: StoreListener[] = [];
  private history: LatestRecord[] = [];
  private fetchState: FetchState = { ok: false, message: '未连接', ts: 0 };
  private revision: number = 0;
  private lastUpdateTs: number = 0;
  private lastRaw: string = '';
  private lastUrl: string = '';

  static get(): AppStore {
    if (AppStore.instance === null) {
      AppStore.instance = new AppStore();
    }
    return AppStore.instance;
  }

  /** 克隆一份设备数据，保证 @State 能观察到变化 */
  static cloneDevice(d: DeviceData): DeviceData {
    return {
      deviceNo: d.deviceNo,
      temp: d.temp,
      humi: d.humi,
      door: d.door,
      radarPresence: d.radarPresence,
      radarMotion: d.radarMotion,
      sos: d.sos,
      alarm: d.alarm,
      alarmType: d.alarmType,
      lastSeen: d.lastSeen,
      serverTs: d.serverTs,
      lastActive: d.lastActive,
      online: d.online
    };
  }

  getDevices(): DeviceData[] {
    let arr: DeviceData[] = [];
    this.devices.forEach((v: DeviceData) => {
      arr.push(v);
    });
    return arr;
  }

  getRevision(): number {
    return this.revision;
  }

  getLastUpdateTs(): number {
    return this.lastUpdateTs;
  }

  getLastRaw(): string {
    return this.lastRaw;
  }

  getLastUrl(): string {
    return this.lastUrl;
  }

  /** 一次性更新设备实时数据 + 历史 + 连接状态，只通知一次 */
  applySnapshot(data: DeviceData, history: LatestRecord[], state: FetchState,
    raw: string, url: string): void {
    let copy: DeviceData = AppStore.cloneDevice(data);
    this.devices.set(copy.deviceNo, copy);
    if (this.selectedDeviceNo < 0) {
      this.selectedDeviceNo = copy.deviceNo;
    }
    this.history = history.slice(0, history.length);
    this.fetchState = state;
    this.lastUpdateTs = state.ts;
    this.lastRaw = raw;
    this.lastUrl = url;
    this.revision = this.revision + 1;
    this.emit();
  }

  /** 写入 / 更新设备实时数据 */
  upsert(data: DeviceData): void {
    this.devices.set(data.deviceNo, AppStore.cloneDevice(data));
    if (this.selectedDeviceNo < 0) {
      this.selectedDeviceNo = data.deviceNo;
    }
    this.revision = this.revision + 1;
    this.emit();
  }

  markOffline(deviceNo: number): void {
    let d: DeviceData | undefined = this.devices.get(deviceNo);
    if (d !== undefined && d.online) {
      let copy: DeviceData = AppStore.cloneDevice(d);
      copy.online = false;
      this.devices.set(deviceNo, copy);
      this.revision = this.revision + 1;
      this.emit();
    }
  }

  /** 切换设备 / 重连前清空内存设备与历史 */
  clearDevices(): void {
    this.devices.clear();
    this.selectedDeviceNo = -1;
    this.history = [];
    this.lastRaw = '';
    this.revision = this.revision + 1;
    this.emit();
  }

  /** 当前选中的设备号；内存中暂无设备时回落到已配置的设备号 */
  getSelectedDeviceNo(): number {
    if (this.selectedDeviceNo >= 0 && this.devices.has(this.selectedDeviceNo)) {
      return this.selectedDeviceNo;
    }
    return ConfigStore.getDeviceNo();
  }

  current(): DeviceData | undefined {
    let d: DeviceData | undefined = this.devices.get(this.getSelectedDeviceNo());
    return d !== undefined ? AppStore.cloneDevice(d) : undefined;
  }

  subscribe(listener: StoreListener): void {
    this.listeners.push(listener);
  }

  unsubscribe(listener: StoreListener): void {
    let idx: number = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  getHistory(): LatestRecord[] {
    return this.history;
  }

  setHistory(list: LatestRecord[]): void {
    this.history = list.slice(0, list.length);
    this.revision = this.revision + 1;
    this.emit();
  }

  getFetchState(): FetchState {
    return this.fetchState;
  }

  setFetchState(state: FetchState): void {
    this.fetchState = state;
    this.lastUpdateTs = state.ts;
    this.revision = this.revision + 1;
    this.emit();
  }

  private emit(): void {
    let arr: DeviceData[] = this.getDevices();
    this.listeners.forEach((l: StoreListener) => {
      l(arr);
    });
  }
}
