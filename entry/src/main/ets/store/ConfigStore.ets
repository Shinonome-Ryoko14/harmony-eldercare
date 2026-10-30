import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { Constants } from '../common/Constants';
import { AiConfig } from '../common/AiTypes';
import { DoorSensorConfig, RoomConfig, RoomSensorConfig } from '../common/Types';

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
  private static baudRate: number = Constants.SERIAL_DEFAULT_BAUD;
  private static deviceUrl: string = '';
  private static aiBaseUrl: string = Constants.AI_DEFAULT_BASE_URL;
  private static aiModel: string = Constants.AI_DEFAULT_MODEL;
  private static aiKey: string = '';
  private static aiStream: boolean = true;
  private static aiTemperature: number = Constants.AI_DEFAULT_TEMPERATURE;
  private static rooms: RoomConfig[] = [];

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
      let bv: preferences.ValueType = await store.get('baud_rate', Constants.SERIAL_DEFAULT_BAUD);
      if (typeof bv === 'number' && (bv as number) > 0) {
        ConfigStore.baudRate = bv as number;
      }
      let uv: preferences.ValueType = await store.get('device_url', '');
      if (typeof uv === 'string') {
        ConfigStore.deviceUrl = uv as string;
      }
      let rv: preferences.ValueType = await store.get('rooms', '');
      if (typeof rv === 'string' && (rv as string).length > 0) {
        try {
          let arr: RoomConfig[] = JSON.parse(rv as string) as RoomConfig[];
          ConfigStore.rooms = ConfigStore.normalizeRooms(arr);
        } catch (e) {
          console.error(`房间配置解析失败: ${JSON.stringify(e)}`);
        }
      }
      // 旧版扁平门窗配置迁移到「未分组」房间
      if (ConfigStore.rooms.length === 0) {
        let sv: preferences.ValueType = await store.get('door_sensors', '');
        if (typeof sv === 'string' && (sv as string).length > 0) {
          try {
            let old: DoorSensorConfig[] = JSON.parse(sv as string) as DoorSensorConfig[];
            if (old.length > 0) {
              let sensors: RoomSensorConfig[] = [];
              for (let i: number = 0; i < old.length; i++) {
                let item: RoomSensorConfig = {
                  id: old[i].id,
                  name: old[i].name,
                  type: 'door',
                  deviceNo: old[i].deviceNo
                };
                sensors.push(item);
              }
              let room: RoomConfig = { id: 'legacy-room', name: '未分组', sensors: sensors };
              ConfigStore.rooms = [room];
              await store.put('rooms', JSON.stringify(ConfigStore.rooms));
              await store.put('door_sensors', '');
              await store.flush();
            }
          } catch (e) {
            console.error(`旧版门窗配置迁移失败: ${JSON.stringify(e)}`);
          }
        }
      }

      let ab: preferences.ValueType = await store.get('ai_base_url', Constants.AI_DEFAULT_BASE_URL);
      if (typeof ab === 'string' && (ab as string).length > 0) {
        ConfigStore.aiBaseUrl = ab as string;
      }
      let am: preferences.ValueType = await store.get('ai_model', Constants.AI_DEFAULT_MODEL);
      if (typeof am === 'string' && (am as string).length > 0) {
        ConfigStore.aiModel = am as string;
      }
      let ak: preferences.ValueType = await store.get('ai_key', '');
      if (typeof ak === 'string') {
        ConfigStore.aiKey = ak as string;
      }
      let asv: preferences.ValueType = await store.get('ai_stream', true);
      if (typeof asv === 'boolean') {
        ConfigStore.aiStream = asv as boolean;
      }
      let at: preferences.ValueType = await store.get('ai_temperature', Constants.AI_DEFAULT_TEMPERATURE);
      if (typeof at === 'number' && (at as number) >= 0 && (at as number) <= 2) {
        ConfigStore.aiTemperature = at as number;
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

  // ==================== 串口配置 ====================

  static getBaudRate(): number {
    return ConfigStore.baudRate;
  }

  /** 设备上报地址（url set 使用），空串表示尚未设置 */
  static getDeviceUrl(): string {
    return ConfigStore.deviceUrl;
  }

  static async saveBaudRate(baud: number): Promise<void> {
    ConfigStore.baudRate = baud;
    let store: preferences.Preferences | null = ConfigStore.store;
    if (store === null) {
      return;
    }
    try {
      await store.put('baud_rate', baud);
      await store.flush();
    } catch (e) {
      console.error(`波特率保存失败: ${JSON.stringify(e)}`);
    }
  }

  static async saveDeviceUrl(url: string): Promise<void> {
    ConfigStore.deviceUrl = url;
    let store: preferences.Preferences | null = ConfigStore.store;
    if (store === null) {
      return;
    }
    try {
      await store.put('device_url', url);
      await store.flush();
    } catch (e) {
      console.error(`上报地址保存失败: ${JSON.stringify(e)}`);
    }
  }

  // ==================== 房间与门窗传感器 ====================

  private static normalizeRooms(list: RoomConfig[]): RoomConfig[] {
    let out: RoomConfig[] = [];
    if (list === null || list === undefined) {
      return out;
    }
    for (let i: number = 0; i < list.length; i++) {
      let r: RoomConfig = list[i];
      if (r === null || r === undefined) {
        continue;
      }
      let sensors: RoomSensorConfig[] = [];
      if (r.sensors !== null && r.sensors !== undefined) {
        for (let j: number = 0; j < r.sensors.length; j++) {
          let s: RoomSensorConfig = r.sensors[j];
          let item: RoomSensorConfig = {
            id: s.id,
            name: s.name,
            type: s.type,
            deviceNo: s.deviceNo
          };
          sensors.push(item);
        }
      }
      let room: RoomConfig = { id: r.id, name: r.name, sensors: sensors };
      out.push(room);
    }
    return out;
  }

  static getRooms(): RoomConfig[] {
    return ConfigStore.normalizeRooms(ConfigStore.rooms);
  }

  static async saveRooms(list: RoomConfig[]): Promise<void> {
    ConfigStore.rooms = ConfigStore.normalizeRooms(list);
    let store: preferences.Preferences | null = ConfigStore.store;
    if (store === null) {
      return;
    }
    try {
      await store.put('rooms', JSON.stringify(ConfigStore.rooms));
      await store.flush();
    } catch (e) {
      console.error(`房间配置保存失败: ${JSON.stringify(e)}`);
    }
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

  // ==================== AI 配置 ====================

  static getAiConfig(): AiConfig {
    return {
      baseUrl: ConfigStore.aiBaseUrl,
      model: ConfigStore.aiModel,
      apiKey: ConfigStore.aiKey,
      stream: ConfigStore.aiStream,
      temperature: ConfigStore.aiTemperature
    };
  }

  static hasAiKey(): boolean {
    return ConfigStore.aiKey.trim().length > 0;
  }

  static async saveAiConfig(cfg: AiConfig): Promise<void> {
    ConfigStore.aiBaseUrl = cfg.baseUrl.trim();
    ConfigStore.aiModel = cfg.model.trim();
    ConfigStore.aiKey = cfg.apiKey.trim();
    ConfigStore.aiStream = cfg.stream;
    ConfigStore.aiTemperature = cfg.temperature;
    let store: preferences.Preferences | null = ConfigStore.store;
    if (store === null) {
      return;
    }
    try {
      await store.put('ai_base_url', ConfigStore.aiBaseUrl);
      await store.put('ai_model', ConfigStore.aiModel);
      await store.put('ai_key', ConfigStore.aiKey);
      await store.put('ai_stream', ConfigStore.aiStream);
      await store.put('ai_temperature', ConfigStore.aiTemperature);
      await store.flush();
    } catch (e) {
      console.error(`AI 配置保存失败: ${JSON.stringify(e)}`);
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
