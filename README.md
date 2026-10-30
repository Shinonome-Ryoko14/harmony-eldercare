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
| 设备配置：USB OTG 串口下发 WiFi / 上报地址命令 | `pages/SettingsPage.ets`、`network/UsbSerialService.ets` |
| **AI 管家（新增）**：结合实时/告警/统计对话、解读告警、生成照护简报 | `pages/AssistantPage.ets`、`network/AiService.ets`、`data/AiContext.ets` |

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
| `door1` | 门窗磁（硬件 0 开 / 1 关，APP 解析时自动归一化） |
| `sos` | 紧急求助（0 正常 / 1 求助） |
| `alarm` / `alarm_type` | 设备报警（0 正常 / 1 报警）及类型 |
| `created_at` | 服务器本地时间 |

> 设备统一以 `device_no` 作为唯一标识，本地 `activity` / `alerts` / `safety_logs` / `samples` 表均按 `device_no` 存储。

---

## 三、目录结构

```
entry/src/main/ets/
  common/      Constants(服务器默认值/字段候选名/阈值/AI提示词)  Protocol(宽松解析+时间)  Types(数据模型)  AiTypes(AI类型/预设)  Theme(配色/玻璃质感参数)
  network/     HttpService(HTTP 轮询 + 解析 + 入库 + 在线判定)
               UsbSerialService(CH340 USB 转串口驱动)
               AiService(OpenAI 兼容 / SSE 流式 / 自动降级 / 取消)
  data/        RdbHelper(SQLite)  Repository(增删查 + 统计)  RuleEngine(告警规则)
               AiContext(业务上下文 + 本地简报)  AiRepository(AI 会话存储)
  store/       AppStore(实时数据全局状态)  ConfigStore(服务器/串口/AI 配置持久化)  AiBus(告警->AI 跳转)
  components/  AppIcon(统一线性图标)  InfoCard(信息卡片)  BarChart(柱状图)  ConnectionBadge(连接状态条)  AiConfigPanel(模型配置)
  pages/       Index(底部导航) Realtime/ReportHub/Report/Alert/Assistant/Stats/Log/Settings
  entryability/EntryAbility.ets   (启动时初始化数据库、配置与 HTTP 服务)
tools/http_simulator.py            (无硬件时的 HTTP 联调模拟服务 + 状态控制台)
tools/ai_mock_server.py            (无 Key / 无外网时的 OpenAI 兼容 Mock 模型)
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

模拟服务自带状态控制台：浏览器打开 `http://<电脑IP>:8000/`，可切换门窗、雷达存在/运动、SOS、报警，并切换“旧字段名 / 时间戳”模式验证 APP 的兼容解析。

### 实时页「接口调试」

实时页状态条下方点「接口调试 ▼」可查看：

- 当前请求地址、刷新次数；
- 解析后的门磁 / 雷达 / SOS / 报警原始值；
- 服务端最近一次响应原文。

若发现卡片不更新，先看这里的原始 JSON 字段名是否正确。

---

## 六、设备设置（USB OTG + CH340）

手机通过 **USB OTG** 连接开发板的 CH340 串口，在 APP 底部「设置」页直接下发设备命令，无需电脑串口助手。

### 使用步骤

1. 用 OTG 转接线把手机与开发板连接（手机作为 USB Host）。
2. 打开「设置」页 →「USB 串口」→「刷新」→ 选择 CH340 设备。
3. 选择波特率（默认 **115200**），点「连接串口」，首次会弹出 USB 授权。
4. 连接成功后可发送：
   - `uart0`（按钮手动发送）
   - `wifi set 名称 密码`
   - `url show`
   - `url set http://IP:端口`
   - `url clear`（恢复固件内置地址，随后自动执行一次 `url show`）
   - 原始命令框可发送任意命令
5. 下方串口控制台显示 TX（发送）与 RX（开发板回显）。

> 命令按原样发送，**不追加换行**；名称/密码允许空格，不加引号。
> 手机侧使用 `@ohos.usbManager` 原始 USB 能力实现 CH340 驱动（`serialManager` 仅支持 PC/2in1），因此工程保持 API 12 即可，无需升级 SDK。

---

## 七、告警规则（APP 端推导，阈值均可在 `Constants.ets` 调整）

- `sos=1` → 紧急求助（最高级）
- `alarm=1` → 设备报警（携带 `alarm_type`）
- 雷达超过 2 小时无“存在/运动” → 长时间无活动
- `door1` 持续开启超过 10 分钟 → 门窗久开
- 温度 / 湿度超出阈值 → 环境异常
- 超过 15 秒未成功拉取 → 设备离线

## 八、闭环处置

告警页点“填写处置结果” → 选择快捷语或自行填写 → 保存 →
写入 `alerts`（标记已处置）与 `safety_logs`（居家安全日志），日志页可历史追溯。

## 九、AI 管家（新增）

底部「AI」Tab 是业务型助手：每次提问都会自动携带**实时传感器数据、今日/昨日活动、近 7 天趋势、最近告警**，
不需要用户自己描述背景。模型统一走 **OpenAI 兼容协议**，免费模型可随时切换。

> 底部导航调整为：实时 / 报告（含趋势统计）/ 告警 / **AI** / 日志 / 设置。

### 9.1 能做什么

- 自然语言问询：今天情况、活动量变化、告警处理建议、家属通知草稿；
- 快捷问句 + 流式打字输出 + 停止生成 / 重试 / 复制 / 清空；
- 告警页「AI 解读」：自动切换到 AI Tab，带着该条告警的完整上下文提问；
- 回答下方「写入处置记录」：一键把 AI 建议写入 `alerts` 与 `safety_logs`，接入原有事件闭环；
- 未配置 Key / 断网：未配置 Key 时自动使用本地规则生成今日简报；断网时错误气泡提供「本地简报」按钮，演示不中断。

### 9.2 配置免费模型（推荐智谱 GLM-4-Flash）

1. 打开 [智谱开放平台](https://open.bigmodel.cn) 注册并创建 API Key（`glm-4-flash` 系列免费）；
2. APP 底部「设置」→「AI 管家模型」，或 AI 页右上角设置按钮；
3. 选择预设「智谱 GLM-4-Flash」，粘贴 Key；
4. 点「测试连接」，成功后再点「保存配置」。

| 配置项 | 默认值 |
| --- | --- |
| Base URL | `https://open.bigmodel.cn/api/paas/v4` |
| 模型名 | `glm-4-flash` |
| 备用平台 | 硅基流动 `https://api.siliconflow.cn/v1` + `Qwen/Qwen2.5-7B-Instruct` |

> 免费模型有并发 / 频率限制，遇到 429 会提示稍后再试；流式失败会自动降级为非流式请求。
> API Key 仅保存在本机 preferences，**不要写进代码或提交到 Git**。

### 9.3 无 Key / 无外网联调

```bash
python3 tools/ai_mock_server.py 8001
```

在 APP 中选「自定义」，填写：

- Base URL：`http://<电脑局域网IP>:8001/v1`
- 模型名：`mock-care`
- API Key：任意非空字符串（如 `test`）

即可验证流式输出、上下文拼装与完整对话流程。

### 9.4 安全与边界

- 只发送聚合后的传感器与统计信息，不发送姓名、地址等个人身份信息；
- system prompt 明确禁止医疗诊断与处方建议，紧急情况优先提示拨打 120 / 联系家属；
- AI 回答仅供参考，页面底部固定展示免责声明。

## 十、房间与门窗传感器

实时页数据卡片下方是「房间」区域：

1. 点「添加房间」，填写房间名（如客厅、阳台）；
2. 点房间卡片进入详情，可单独添加门传感器或窗传感器；
3. 每个传感器填写名称与设备号（`device_no`），保存后立即生成状态行；
4. APP 按轮询周期分别读取每个设备号，显示在线状态与开 / 关状态；
5. 房间与传感器配置保存在本机 preferences，重启不丢失；详情页可删除传感器或整个房间。

> 房间只是本地分组，不额外占用协议字段；每个传感器仍按独立 `device_no` 轮询现有的 `door1` 状态。
> 旧版扁平门窗配置会在首次启动时自动迁移到「未分组」房间。
