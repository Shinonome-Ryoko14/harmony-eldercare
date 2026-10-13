import relationalStore from '@ohos.data.relationalStore';
import { common } from '@kit.AbilityKit';

const STORE_CONFIG: relationalStore.StoreConfig = {
  name: 'eldercare.db',
  securityLevel: relationalStore.SecurityLevel.S1
};

/**
 * 数据库版本。所有表都以 device_no（INTEGER）作为设备标识。
 * 版本不一致时重建全部表（本地缓存数据可重新从服务端累积）。
 */
const DB_VERSION: number = 2;

const TABLES: string[] = ['activity', 'alerts', 'safety_logs', 'samples'];

const SQL_CREATE_ACTIVITY: string =
  'CREATE TABLE IF NOT EXISTS activity (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
  'device_no INTEGER NOT NULL, ts INTEGER NOT NULL, count INTEGER NOT NULL DEFAULT 0)';

const SQL_CREATE_ALERTS: string =
  'CREATE TABLE IF NOT EXISTS alerts (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
  'device_no INTEGER NOT NULL, ts INTEGER NOT NULL, ' +
  'type TEXT NOT NULL, level INTEGER NOT NULL DEFAULT 0, ' +
  'message TEXT NOT NULL DEFAULT \'\', ' +
  'handled INTEGER NOT NULL DEFAULT 0, ' +
  'handle_result TEXT NOT NULL DEFAULT \'\', ' +
  'handle_ts INTEGER NOT NULL DEFAULT 0)';

const SQL_CREATE_LOGS: string =
  'CREATE TABLE IF NOT EXISTS safety_logs (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
  'alert_id INTEGER NOT NULL DEFAULT 0, ' +
  'device_no INTEGER NOT NULL, alert_type TEXT NOT NULL DEFAULT \'\', ' +
  'result TEXT NOT NULL DEFAULT \'\', ' +
  'operator TEXT NOT NULL DEFAULT \'\', ' +
  'ts INTEGER NOT NULL)';

/** 服务端采样记录（本地累积，用于历史与统计；device_no + remote_id 唯一去重） */
const SQL_CREATE_SAMPLES: string =
  'CREATE TABLE IF NOT EXISTS samples (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
  'device_no INTEGER NOT NULL, remote_id INTEGER NOT NULL, ' +
  'ts INTEGER NOT NULL, ' +
  'temp REAL NOT NULL DEFAULT 0, humi REAL NOT NULL DEFAULT 0, ' +
  'radar_presence INTEGER NOT NULL DEFAULT 0, radar_motion INTEGER NOT NULL DEFAULT 0, ' +
  'door1 INTEGER NOT NULL DEFAULT 0, sos INTEGER NOT NULL DEFAULT 0, ' +
  'alarm INTEGER NOT NULL DEFAULT 0, alarm_type TEXT NOT NULL DEFAULT \'\', ' +
  'UNIQUE(device_no, remote_id))';

/**
 * 关系型数据库（SQLite）初始化与单例获取。
 */
export class RdbHelper {
  private static store: relationalStore.RdbStore | null = null;

  static async init(context: common.Context): Promise<void> {
    if (RdbHelper.store !== null) {
      return;
    }
    try {
      let store: relationalStore.RdbStore = await relationalStore.getRdbStore(context, STORE_CONFIG);
      if (store.version !== DB_VERSION) {
        await RdbHelper.recreate(store);
        store.version = DB_VERSION;
      }
      RdbHelper.store = store;
    } catch (err) {
      console.error(`数据库初始化失败: ${JSON.stringify(err)}`);
      throw err as Error;
    }
  }

  /** 版本升级：清空并重建全部表（设备标识由 ip 迁移为 device_no） */
  private static async recreate(store: relationalStore.RdbStore): Promise<void> {
    for (let i: number = 0; i < TABLES.length; i++) {
      await store.executeSql(`DROP TABLE IF EXISTS ${TABLES[i]}`);
    }
    await store.executeSql(SQL_CREATE_ACTIVITY);
    await store.executeSql(SQL_CREATE_ALERTS);
    await store.executeSql(SQL_CREATE_LOGS);
    await store.executeSql(SQL_CREATE_SAMPLES);
  }

  static get(): relationalStore.RdbStore {
    if (RdbHelper.store === null) {
      throw new Error('RdbHelper 未初始化');
    }
    return RdbHelper.store;
  }
}
