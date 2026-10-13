import { DeviceData, FetchState, LatestRecord } from '../common/Types';

export type StoreListener = (devices: DeviceData[]) => void;

/**
 * 全局内存状态：保存所有已发现设备的实时数据，并通知订阅者。
 */
export class AppStore {
  private static instance: AppStore | null = null;
  private devices: Map<string, DeviceData> = new Map<string, DeviceData>();
  private selectedIp: string = '';
  private listeners: StoreListener[] = [];
  private history: LatestRecord[] = [];
  private fetchState: FetchState = { ok: false, message: '未连接', ts: 0 };

  static get(): AppStore {
    if (AppStore.instance === null) {
      AppStore.instance = new AppStore();
    }
    return AppStore.instance;
  }

  getDevices(): DeviceData[] {
    let arr: DeviceData[] = [];
    this.devices.forEach((v: DeviceData) => {
      arr.push(v);
    });
    return arr;
  }

  hasDevice(ip: string): boolean {
    return this.devices.has(ip);
  }

  getDevice(ip: string): DeviceData | undefined {
    return this.devices.get(ip);
  }

  /** 首次发现设备时返回 true */
  upsert(data: DeviceData): boolean {
    let isNew: boolean = !this.devices.has(data.ip);
    this.devices.set(data.ip, data);
    if (this.selectedIp.length === 0) {
      this.selectedIp = data.ip;
    }
    this.emit();
    return isNew;
  }

  markOffline(ip: string): void {
    let d: DeviceData | undefined = this.devices.get(ip);
    if (d !== undefined && d.online) {
      d.online = false;
      this.devices.set(ip, d);
      this.emit();
    }
  }

  getSelectedIp(): string {
    if (this.selectedIp.length > 0 && this.devices.has(this.selectedIp)) {
      return this.selectedIp;
    }
    let arr: DeviceData[] = this.getDevices();
    return arr.length > 0 ? arr[0].ip : '';
  }

  setSelectedIp(ip: string): void {
    this.selectedIp = ip;
    this.emit();
  }

  current(): DeviceData | undefined {
    let ip: string = this.getSelectedIp();
    if (ip.length === 0) {
      return undefined;
    }
    return this.devices.get(ip);
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
    this.history = list;
    this.emit();
  }

  getFetchState(): FetchState {
    return this.fetchState;
  }

  setFetchState(state: FetchState): void {
    this.fetchState = state;
    this.emit();
  }

  private emit(): void {
    let arr: DeviceData[] = this.getDevices();
    this.listeners.forEach((l: StoreListener) => {
      l(arr);
    });
  }
}
