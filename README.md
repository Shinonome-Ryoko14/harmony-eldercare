# 居家守护 · OpenHarmony 手机 APP

面向“北向 OpenHarmony 手机 APP + 硬件网关 HTTP 通信”的完整工程。硬件端已完成全部逻辑，
手机 APP 负责：**HTTP 轮询数据服务器 → 解析报文 → 实时展示 → 告警闭环处置 → 统计图表**。

> 详细操作手册见 [`使用说明.md`](./使用说明.md)。

---

## 一、功能与评审点对照

| 需求 | 实现位置 |
| --- | --- |
| 实时查看：人体最后活动时间、门窗记录、室内温湿度、设备在线状态 | `entry/src/main/ets/pages/RealtimePage.ets` |
| 老人活动规律报告（今日活动频次 vs 昨日） | `entry/src/main/ets/pages/ReportPage.ets` |
| 历史预警记录查询（告警时间、类型） | `entry/src/main/ets/pages/AlertPage.ets` |
| **事件闭环管理（评审重点）**：填写处置结果 + 居家安全日志 | `pages/AlertPage.ets`、`pages/LogPage.ets` |
| 数据统计分析：周/月活动趋势、时段分布、活动量下降风险提示 | `pages/StatsPage.ets`、`pages/ReportPage.ets` |

---

## 二、通信设计

APP 作为 HTTP 客户端，**轮询**局域网内的数据服务器（每次接入的路由不同，**IP/端口/设备号都可在 APP 内修改并保存，不写死**）。

- 默认服务器：`http://10.19.81.90:8000`（实时页顶部「服务器设置」里可改，保存在本机 preferences）
- 拉取接口（每 3 秒一次）：
  ```
  GET http://{IP}:{PORT}/api/device/latest/?device_no={n}&limit=10
  ```
- 响应格式：
  ```json
  {"code":0,"latest":{"id":168,"device_no":0,"temp":25.4,"humi":52.0,
   "radar_presence":0,"radar_motion":0,"door1":0,"sos":0,"alarm":0,
   "alarm_type":"","created_at":"2026-10-13 06:27:57"},
   "history":[ ...同上结构，按 id 倒序，最多 limit 条... ]}
  ```
- 解析：`code` 必须为 0；`latest` + `history` 合并且按 `id` 去重；**新记录**写入本地 `samples` 表并推导活动/告警；
  **每次成功拉取都会刷新界面实时数据与在线状态**（即使没有新记录）
- 在线判定：以本地成功拉取时间为准，超过 15 秒未更新判为离线
- 网页查看页：直接在浏览器打开 `http://{IP}:{PORT}`

| 字段 | 含义 |
| --- | --- |
| `temp` | 室内温度(℃) |
| `humi` | 室内湿度(%) |
| `radar_presence` | 雷达存在（0 无 / 1 有） |
| `radar_motion` | 雷达运动（0 无 / 1 有） |
| `door1` | 门窗磁（0 关 / 1 开） |
| `sos` | 紧急求助（0 正常 / 1 求助） |
| `alarm` / `alarm_type` | 设备报警（0 正常 / 1 报警）及类型 |
| `created_at` | 服务器本地时间 |

> 设备统一以 `device_no` 作为唯一标识，本地 `activity` / `alerts` / `safety_logs` / `samples` 表均按 `device_no` 存储。

---

## 三、目录结构

```
entry/src/main/ets/
  common/      Constants(服务器默认值/字段映射/阈值)  Protocol(报文解析+时间)  Types(数据模型)  Theme(配色)
  network/     HttpService(HTTP 轮询 + 解析 + 入库 + 在线判定)
  data/        RdbHelper(SQLite)  Repository(增删查 + 统计)  RuleEngine(告警规则)
  store/       AppStore(实时数据全局状态)  ConfigStore(服务器配置持久化)
  components/  InfoCard(信息卡片)  BarChart(柱状图)  ConnectionBadge(连接状态条)
  pages/       Index(底部导航) Realtime/Report/Alert/Stats/Log
  entryability/EntryAbility.ets   (启动时初始化数据库、配置与 HTTP 服务)
tools/http_simulator.py            (无硬件时的 HTTP 联调模拟服务)
```

---

## 四、运行步骤（DevEco Studio）

1. 安装 **DevEco Studio 5.0**（自带 OpenHarmony SDK，API 12）。
2. `File → Open` 打开本工程目录。
3. 首次会自动同步依赖，按提示配置**自动签名**（Signing Configs → Automatically generate signature）。
4. 连接手机或启动模拟器，点击运行 ▶。

> 建议将工程放在**纯英文路径**下（如 `D:\harmony\eldercare`），避免中文/空格路径导致构建异常。

---

## 五、联调（无硬件时）

APP 是 HTTP 客户端，联调只需一个能返回上面 JSON 的服务端：

- 直接使用硬件方提供的服务（浏览器打开 `http://{IP}:{PORT}` 应能看到网页查看页）；
- 或运行本工程自带的模拟服务，然后在 APP 实时页顶部「服务器设置」填入电脑的局域网 IP 与端口，点「保存并重连」：
  ```bash
  python3 tools/http_simulator.py 8000
  ```

> APP 与服务器需在同一局域网；手机访问电脑服务时注意关闭电脑防火墙对 8000 端口的拦截。

---

## 六、告警规则（APP 端推导，阈值均可在 `Constants.ets` 调整）

- `sos=1` → 紧急求助（最高级）
- `alarm=1` → 设备报警（携带 `alarm_type`）
- 雷达超过 2 小时无“存在/运动” → 长时间无活动
- `door1` 持续开启超过 10 分钟 → 门窗久开
- 温度 / 湿度超出阈值 → 环境异常
- 超过 15 秒未成功拉取 → 设备离线

## 七、闭环处置

告警页点“填写处置结果” → 选择快捷语或自行填写 → 保存 →
写入 `alerts`（标记已处置）与 `safety_logs`（居家安全日志），日志页可历史追溯。
