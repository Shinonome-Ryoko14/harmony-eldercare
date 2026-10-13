import { DeviceData, FetchState, LatestRecord } from '../common/Types';
import { ConfigStore } from './ConfigStore';

export type StoreListener = (devices: DeviceData[]) => void;

/**
 * 全局内存状态：保存各设备的实时数据、最近上报历史与拉取状态，并通知订阅者。
 * 设备以 deviceNo 唯一标识。
 */
export class AppStore {
  private static instance: AppStore | null = null;
  private devices: Map<number, DeviceData> = new Map<number, DeviceData>();
  private selectedDeviceNo: number = -1;
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

  /** 写入 / 更新设备实时数据 */
  upsert(data: DeviceData): void {
    this.devices.set(data.deviceNo, data);
    if (this.selectedDeviceNo < 0) {
      this.selectedDeviceNo = data.deviceNo;
    }
    this.emit();
  }

  markOffline(deviceNo: number): void {
    let d: DeviceData | undefined = this.devices.get(deviceNo);
    if (d !== undefined && d.online) {
      d.online = false;
      this.devices.set(deviceNo, d);
      this.emit();
    }
  }

  /** 切换设备 / 重连前清空内存设备与历史 */
  clearDevices(): void {
    this.devices.clear();
    this.selectedDeviceNo = -1;
    this.history = [];
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
    return this.devices.get(this.getSelectedDeviceNo());
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
