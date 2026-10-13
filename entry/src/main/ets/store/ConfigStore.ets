import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { Constants } from '../common/Constants';

const STORE_NAME: string = 'eldercare_cfg';

/**
 * 服务器配置存储：host / port / deviceNo / pollMs。
 * 使用 preferences 持久化，重启不丢；读取失败时回落到默认值。
 */
export class ConfigStore {
  private static store: preferences.Preferences | null = null;
  private static host: string = Constants.HTTP_DEFAULT_HOST;
  private static port: number = Constants.HTTP_DEFAULT_PORT;
  private static deviceNo: number = Constants.HTTP_DEFAULT_DEVICE_NO;
  private static pollMs: number = Constants.HTTP_POLL_INTERVAL;

  /** 应用启动时调用，加载已保存的配置 */
  static async init(context: common.Context): Promise<void> {
    try {
      let options: preferences.Options = { name: STORE_NAME };
      let store: preferences.Preferences = await preferences.getPreferences(context, options);
      ConfigStore.store = store;

      let hv: preferences.ValueType = await store.get('host', Constants.HTTP_DEFAULT_HOST);
      if (typeof hv === 'string' && (hv as string).length > 0) {
        ConfigStore.host = hv as string;
      }
      let pv: preferences.ValueType = await store.get('port', Constants.HTTP_DEFAULT_PORT);
      if (typeof pv === 'number' && (pv as number) > 0) {
        ConfigStore.port = pv as number;
      }
      let dv: preferences.ValueType = await store.get('device_no', Constants.HTTP_DEFAULT_DEVICE_NO);
      if (typeof dv === 'number') {
        ConfigStore.deviceNo = dv as number;
      }
      let mv: preferences.ValueType = await store.get('poll_ms', Constants.HTTP_POLL_INTERVAL);
      if (typeof mv === 'number' && (mv as number) >= 1000) {
        ConfigStore.pollMs = mv as number;
      }
    } catch (e) {
      console.error(`配置加载失败: ${JSON.stringify(e)}`);
    }
  }

  static getHost(): string {
    return ConfigStore.host;
  }

  static getPort(): number {
    return ConfigStore.port;
  }

  static getDeviceNo(): number {
    return ConfigStore.deviceNo;
  }

  static getPollMs(): number {
    return ConfigStore.pollMs;
  }

  /** 保存并持久化 */
  static async save(host: string, port: number, deviceNo: number, pollMs: number): Promise<void> {
    ConfigStore.host = host;
    ConfigStore.port = port;
    ConfigStore.deviceNo = deviceNo;
    ConfigStore.pollMs = pollMs;
    let store: preferences.Preferences | null = ConfigStore.store;
    if (store === null) {
      return;
    }
    try {
      await store.put('host', host);
      await store.put('port', port);
      await store.put('device_no', deviceNo);
      await store.put('poll_ms', pollMs);
      await store.flush();
    } catch (e) {
      console.error(`配置保存失败: ${JSON.stringify(e)}`);
    }
  }

  /** 形如 http://host:port */
  static baseUrl(): string {
    return `http://${ConfigStore.host}:${ConfigStore.port}`;
  }

  /** 拼出带 limit 的接口地址 */
  static apiUrl(limit: number): string {
    return `${ConfigStore.baseUrl()}${Constants.HTTP_API_PATH}?device_no=${ConfigStore.deviceNo}&limit=${limit}`;
  }
}
