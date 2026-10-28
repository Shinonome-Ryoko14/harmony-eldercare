import relationalStore from '@ohos.data.relationalStore';
import { RdbHelper } from './RdbHelper';
import { AiMessageRecord } from '../common/AiTypes';

/**
 * AI 会话消息的本地存储。
 * 表结构见 RdbHelper：ai_messages(id, device_no, role, content, ts)。
 */
export class AiRepository {

  static async add(deviceNo: number, role: string, content: string): Promise<void> {
    if (content.length === 0) {
      return;
    }
    try {
      let bucket: relationalStore.ValuesBucket = {
        'device_no': deviceNo,
        'role': role,
        'content': content,
        'ts': Date.now()
      };
      await RdbHelper.get().insert('ai_messages', bucket);
    } catch (err) {
      // 会话留存失败不能影响正常对话
      console.error(`写入 AI 消息失败: ${JSON.stringify(err)}`);
    }
  }

  /** 最近 limit 条消息，返回按时间正序（旧 -> 新） */
  static async recent(limit: number): Promise<AiMessageRecord[]> {
    let list: AiMessageRecord[] = [];
    try {
      let pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('ai_messages');
      pred.orderByDesc('id');
      pred.limitAs(limit);
      let rs: relationalStore.ResultSet = await RdbHelper.get().query(pred);
      while (rs.goToNextRow()) {
        list.push({
          id: rs.getLong(rs.getColumnIndex('id')),
          role: rs.getString(rs.getColumnIndex('role')),
          content: rs.getString(rs.getColumnIndex('content')),
          ts: rs.getLong(rs.getColumnIndex('ts'))
        });
      }
      rs.close();
    } catch (err) {
      console.error(`读取 AI 消息失败: ${JSON.stringify(err)}`);
      return [];
    }
    // 数据库按 id 倒序取出，这里反转成正常对话顺序
    let ordered: AiMessageRecord[] = [];
    for (let i: number = list.length - 1; i >= 0; i--) {
      ordered.push(list[i]);
    }
    return ordered;
  }

  static async clear(): Promise<void> {
    try {
      let pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('ai_messages');
      await RdbHelper.get().delete(pred);
    } catch (err) {
      console.error(`清空 AI 消息失败: ${JSON.stringify(err)}`);
    }
  }
}
