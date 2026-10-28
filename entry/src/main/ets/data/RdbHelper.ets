import relationalStore from '@ohos.data.relationalStore';
import { common } from '@kit.AbilityKit';

const STORE_CONFIG: relationalStore.StoreConfig = {
  name: 'eldercare.db',
  securityLevel: relationalStore.SecurityLevel.S1
};

/**
 * 数据库版本。
 * v3：新增 AI 会话表 ai_messages（v2 -> v3 走增量迁移，保留业务数据）。
 * 更低版本（v0/v1）与当前结构差异较大，仍整体重建。
 */
const DB_VERSION: number = 3;

const TABLES: string[] = ['activity', 'alerts', 'safety_logs', 'samples', 'ai_messages'];

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

/** AI 对话消息（本地留存最近若干条，便于重启后继续查看） */
const SQL_CREATE_AI_MESSAGES: string =
  'CREATE TABLE IF NOT EXISTS ai_messages (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
  'device_no INTEGER NOT NULL DEFAULT 0, ' +
  'role TEXT NOT NULL, ' +
  'content TEXT NOT NULL, ' +
  'ts INTEGER NOT NULL)';

/**
 * 关系型数据库（SQLite）初始化与单例获取。
 */
export class RdbHelper {
  private static store: relationalStore.RdbStore | null = null;
  private static initPromise: Promise<void> | null = null;

  /** 数据库是否已就绪（供服务层在启动前判断） */
  static isReady(): boolean {
    return RdbHelper.store !== null;
  }

  static async init(context: common.Context): Promise<void> {
    if (RdbHelper.store !== null) {
      return;
    }
    // 并发调用时复用同一个初始化过程，避免重复建库/重建表
    if (RdbHelper.initPromise !== null) {
      await RdbHelper.initPromise;
      return;
    }
    let task: Promise<void> = RdbHelper.doInit(context);
    RdbHelper.initPromise = task;
    try {
      await task;
    } finally {
      RdbHelper.initPromise = null;
    }
  }

  private static async doInit(context: common.Context): Promise<void> {
    try {
      let store: relationalStore.RdbStore = await relationalStore.getRdbStore(context, STORE_CONFIG);
      if (store.version !== DB_VERSION) {
        await RdbHelper.migrate(store, store.version);
        store.version = DB_VERSION;
      }
      RdbHelper.store = store;
      console.info('数据库初始化完成');
    } catch (err) {
      console.error(`数据库初始化失败: ${JSON.stringify(err)}`);
      throw err as Error;
    }
  }

  /**
   * 版本迁移。
   * v2 -> v3：只新增 ai_messages 表，保留 samples / activity / alerts / safety_logs。
   * 其他旧版本（含全新库）：结构差异较大，整体重建。
   */
  private static async migrate(store: relationalStore.RdbStore, oldVersion: number): Promise<void> {
    if (oldVersion === 2) {
      await store.executeSql(SQL_CREATE_AI_MESSAGES);
      console.info('数据库迁移完成：v2 -> v3（仅新增 AI 会话表）');
      return;
    }
    await RdbHelper.recreate(store);
  }

  /** 整体重建（仅在结构不兼容的旧版本或全新库时使用） */
  private static async recreate(store: relationalStore.RdbStore): Promise<void> {
    try {
      for (let i: number = 0; i < TABLES.length; i++) {
        await store.executeSql(`DROP TABLE IF EXISTS ${TABLES[i]}`);
      }
      await store.executeSql(SQL_CREATE_ACTIVITY);
      await store.executeSql(SQL_CREATE_ALERTS);
      await store.executeSql(SQL_CREATE_LOGS);
      await store.executeSql(SQL_CREATE_SAMPLES);
      await store.executeSql(SQL_CREATE_AI_MESSAGES);
    } catch (err) {
      console.error(`重建数据表失败: ${JSON.stringify(err)}`);
      throw err as Error;
    }
  }

  static get(): relationalStore.RdbStore {
    if (RdbHelper.store === null) {
      throw new Error('RdbHelper 未初始化');
    }
    return RdbHelper.store;
  }
}
