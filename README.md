# 居家守护 · OpenHarmony 手机 APP

面向“北向 OpenHarmony 手机 APP + 硬件网关 UDP 通信”的完整工程。硬件端已完成全部逻辑，
手机 APP 负责：**发送 UDP 探测包 → 接收硬件报文 → 实时展示 → 告警闭环处置 → 统计图表**。

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

- 端口：**8888**（在 `entry/src/main/ets/common/Constants.ets` 中修改）
- APP 每 3 秒向 `255.255.255.255:8888` 广播探测包 `ELDER_CARE_DISCOVER`
- 硬件收到探测包后，把数据回发到 APP 的来源地址
- 报文格式（字段可能变动）：
  ```json
  {"temp":26.5,"humi":34,"magnet":0,"pulse":0,"total":0,"sos":0}
  ```
- **设备发现**：以报文的来源 IP 作为设备标识，自动加入设备列表（即“扫描可用 IP”）
- **在线判定**：超过 10 秒未收到报文即判为离线
- **字段名变更**：只需修改 `Constants.ets` 中的 `FIELD_KEYS`

| 字段 | 含义 |
| --- | --- |
| `temp` | 室内温度(℃) |
| `humi` | 室内湿度(%) |
| `magnet` | 门窗磁（0 关 / 1 开） |
| `pulse` | 人体活动（0 无 / 1 有） |
| `total` | 累计活动次数 |
| `sos` | 紧急求助（0 正常 / 1 求助） |

---

## 三、目录结构

```
entry/src/main/ets/
  common/      Constants(端口/字段映射)  Protocol(报文解析)  Types(数据模型)  Theme(配色)
  network/     UdpService(探测包 + 收包 + 在线判定)
  data/        RdbHelper(SQLite)  Repository(增删查 + 统计)  RuleEngine(告警规则)
  store/       AppStore(实时数据全局状态)
  components/  InfoCard(信息卡片)  BarChart(柱状图)
  pages/       Index(底部导航) Realtime/Report/Alert/Stats/Log
  entryability/EntryAbility.ets   (启动时初始化数据库与 UDP)
tools/udp_simulator.py             (硬件 UDP 模拟器)
```

---

## 四、运行步骤（DevEco Studio）

1. 安装 **DevEco Studio 5.0**（自带 OpenHarmony SDK，API 12）。
2. `File → Open` 打开本工程目录。
3. 首次会自动同步依赖，按提示配置**自动签名**（Signing Configs → Automatically generate signature）。
4. 连接手机或启动模拟器，点击运行 ▶。

> 建议将工程放在**纯英文路径**下（如 `D:\harmony\eldercare`），避免中文/空格路径导致构建异常。

---

## 五、无硬件时联调

工程自带模拟器脚本 `tools/udp_simulator.py`（电脑与手机/模拟器需在同一局域网）：

```bash
python3 tools/udp_simulator.py                # 监听 8888，收到 APP 探测包即回复数据
python3 tools/udp_simulator.py --interval 2   # 额外每 2 秒主动广播
python3 tools/udp_simulator.py --sos          # 模拟一次 SOS 告警
```

> 模拟器与 APP 不能在同一台设备上同时占用 8888 端口：让脚本跑在电脑、APP 跑在手机/模拟器上。

---

## 六、告警规则（APP 端推导，阈值均可在 `Constants.ets` 调整）

- `sos=1` → 紧急求助（最高级）
- 超过 2 小时无活动 → 长时间无活动
- 门窗持续开启超过 10 分钟 → 门窗久开
- 温度 / 湿度超出阈值 → 环境异常
- 设备超时未上报 → 设备离线

## 七、闭环处置

告警页点“填写处置结果” → 选择快捷语或自行填写 → 保存 →
写入 `alerts`（标记已处置）与 `safety_logs`（居家安全日志），日志页可历史追溯。
