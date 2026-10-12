import relationalStore from '@ohos.data.relationalStore';
import { common } from '@kit.AbilityKit';

const STORE_CONFIG: relationalStore.StoreConfig = {
  name: 'eldercare.db',
  securityLevel: relationalStore.SecurityLevel.S1
};

const SQL_CREATE_ACTIVITY: string =
  'CREATE TABLE IF NOT EXISTS activity (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
  'ip TEXT NOT NULL, ts INTEGER NOT NULL, count INTEGER NOT NULL DEFAULT 0)';

const SQL_CREATE_ALERTS: string =
  'CREATE TABLE IF NOT EXISTS alerts (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
  'ip TEXT NOT NULL, ts INTEGER NOT NULL, ' +
  'type TEXT NOT NULL, level INTEGER NOT NULL DEFAULT 0, ' +
  'message TEXT NOT NULL DEFAULT \'\', ' +
  'handled INTEGER NOT NULL DEFAULT 0, ' +
  'handle_result TEXT NOT NULL DEFAULT \'\', ' +
  'handle_ts INTEGER NOT NULL DEFAULT 0)';

const SQL_CREATE_LOGS: string =
  'CREATE TABLE IF NOT EXISTS safety_logs (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
  'alert_id INTEGER NOT NULL DEFAULT 0, ' +
  'ip TEXT NOT NULL, alert_type TEXT NOT NULL DEFAULT \'\', ' +
  'result TEXT NOT NULL DEFAULT \'\', ' +
  'operator TEXT NOT NULL DEFAULT \'\', ' +
  'ts INTEGER NOT NULL)';

/**
 * 关系型数据库（SQLite）初始化与单例获取。
 */
export class RdbHelper {
  private static store: relationalStore.RdbStore | null = null;

  static async init(context: common.Context): Promise<void> {
    if (RdbHelper.store !== null) {
      return;
    }
    let store: relationalStore.RdbStore = await relationalStore.getRdbStore(context, STORE_CONFIG);
    await store.executeSql(SQL_CREATE_ACTIVITY);
    await store.executeSql(SQL_CREATE_ALERTS);
    await store.executeSql(SQL_CREATE_LOGS);
    RdbHelper.store = store;
  }

  static get(): relationalStore.RdbStore {
    if (RdbHelper.store === null) {
      throw new Error('RdbHelper 未初始化');
    }
    return RdbHelper.store;
  }
}
