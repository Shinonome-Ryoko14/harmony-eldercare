import { DeviceData, LatestRecord, RoomConfig, RoomSensorConfig } from '../common/Types';
import { Constants } from '../common/Constants';
import { DateUtil } from '../common/Protocol';
import { Theme } from '../common/Theme';
import { AppStore, StoreListener } from '../store/AppStore';
import { ConfigStore } from '../store/ConfigStore';
import { HttpService } from '../network/HttpService';
import { InfoCard } from '../components/InfoCard';
import { AppIcon } from '../components/AppIcon';

const EMPTY_DEVICE: DeviceData = {
  deviceNo: 0,
  temp: 0,
  humi: 0,
  door: 0,
  radarPresence: 0,
  radarMotion: 0,
  sos: 0,
  alarm: 0,
  alarmType: '',
  lastSeen: 0,
  serverTs: 0,
  lastActive: 0,
  online: false
};

/** 房间内传感器的展示状态 */
interface SensorView {
  id: string;
  roomId: string;
  name: string;
  type: string;
  deviceNo: number;
  /** -1 表示尚未读取到 */
  door: number;
  online: boolean;
  ts: number;
}

@Component
export struct RealtimePage {
  @State current: DeviceData = EMPTY_DEVICE;
  @State history: LatestRecord[] = [];
  @State fetchOk: boolean = false;
  @State fetchMsg: string = '未连接';
  @State showSettings: boolean = false;
  @State showDebug: boolean = false;
  @State hostInput: string = '';
  @State portInput: string = '';
  @State deviceInput: string = '';
  @State lastUpdate: number = 0;
  @State lastRaw: string = '';
  @State revision: number = 0;
  @State rooms: RoomConfig[] = [];
  @State sensorViews: SensorView[] = [];
  @State showAddRoom: boolean = false;
  @State roomNameInput: string = '';
  @State showRoomDetail: boolean = false;
  @State activeRoomId: string = '';
  @State sensorNameInput: string = '';
  @State sensorDeviceInput: string = '';
  @State sensorType: string = 'door';
  private sensorTimer: number = -1;
  private sensorFetching: boolean = false;

  private listener: StoreListener = () => {
    let store: AppStore = AppStore.get();
    let cur: DeviceData | undefined = store.current();
    this.current = cur !== undefined ? cur : EMPTY_DEVICE;
    let history: LatestRecord[] = store.getHistory();
    this.history = history.slice(0, history.length);
    this.fetchOk = store.getFetchState().ok;
    this.fetchMsg = store.getFetchState().message;
    if (this.fetchOk) {
      this.lastUpdate = store.getLastUpdateTs();
    }
    this.lastRaw = store.getLastRaw();
    this.revision = store.getRevision();
  };

  aboutToAppear(): void {
    AppStore.get().subscribe(this.listener);
    this.listener(AppStore.get().getDevices());
    this.hostInput = ConfigStore.getHost();
    this.portInput = `${ConfigStore.getPort()}`;
    this.deviceInput = `${ConfigStore.getDeviceNo()}`;
    this.rooms = ConfigStore.getRooms();
    this.sensorViews = this.toSensorViews(this.rooms);
    this.refreshSensors();
    this.sensorTimer = setInterval(() => {
      this.refreshSensors();
    }, ConfigStore.getPollMs());
  }

  aboutToDisappear(): void {
    AppStore.get().unsubscribe(this.listener);
    if (this.sensorTimer !== -1) {
      clearInterval(this.sensorTimer);
      this.sensorTimer = -1;
    }
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (err) {
      console.error(`提示弹出失败: ${JSON.stringify(err)}`);
    }
  }

  // ---------------- 房间与门窗传感器 ----------------

  private toSensorViews(rooms: RoomConfig[]): SensorView[] {
    let views: SensorView[] = [];
    for (let i: number = 0; i < rooms.length; i++) {
      let room: RoomConfig = rooms[i];
      for (let j: number = 0; j < room.sensors.length; j++) {
        let cfg: RoomSensorConfig = room.sensors[j];
        let old: SensorView | null = null;
        for (let k: number = 0; k < this.sensorViews.length; k++) {
          if (this.sensorViews[k].id === cfg.id) {
            old = this.sensorViews[k];
          }
        }
        let view: SensorView = {
          id: cfg.id,
          roomId: room.id,
          name: cfg.name,
          type: cfg.type,
          deviceNo: cfg.deviceNo,
          door: old !== null ? old.door : -1,
          online: old !== null ? old.online : false,
          ts: old !== null ? old.ts : 0
        };
        views.push(view);
      }
    }
    return views;
  }

  private async refreshSensors(): Promise<void> {
    if (this.sensorFetching || this.sensorViews.length === 0) {
      return;
    }
    this.sensorFetching = true;
    let current: SensorView[] = this.sensorViews.slice(0, this.sensorViews.length);
    let next: SensorView[] = [];
    try {
      for (let i: number = 0; i < current.length; i++) {
        let v: SensorView = current[i];
        let d: DeviceData | null = await HttpService.fetchSensor(v.deviceNo);
        let row: SensorView = {
          id: v.id,
          roomId: v.roomId,
          name: v.name,
          type: v.type,
          deviceNo: v.deviceNo,
          door: d !== null ? d.door : v.door,
          online: d !== null,
          ts: d !== null ? (d.serverTs > 0 ? d.serverTs : Date.now()) : v.ts
        };
        next.push(row);
      }
      this.sensorViews = next;
    } finally {
      this.sensorFetching = false;
    }
  }

  private sensorTypeLabel(v: SensorView): string {
    return v.type === 'window' ? '窗' : '门';
  }

  private sensorIcon(v: SensorView): string {
    return v.type === 'window' ? 'window' : 'door';
  }

  private sensorValue(v: SensorView): string {
    if (v.door < 0) {
      return '读取中';
    }
    if (!v.online) {
      return '未连接';
    }
    return v.door === 1 ? '开启' : '关闭';
  }

  private sensorAccent(v: SensorView): string {
    if (v.door < 0 || !v.online) {
      return Theme.SUB;
    }
    return v.door === 1 ? Theme.WARN : Theme.OK;
  }

  private sensorSubtitle(v: SensorView): string {
    let state: string = v.online ? '在线' : (v.door < 0 ? '读取中' : '离线');
    return `${this.sensorTypeLabel(v)} · 设备号 ${v.deviceNo} · ${state}`;
  }

  private roomSensorCount(roomId: string): number {
    let count: number = 0;
    for (let i: number = 0; i < this.sensorViews.length; i++) {
      if (this.sensorViews[i].roomId === roomId) {
        count = count + 1;
      }
    }
    return count;
  }

  private roomOpenCount(roomId: string): number {
    let count: number = 0;
    for (let i: number = 0; i < this.sensorViews.length; i++) {
      let v: SensorView = this.sensorViews[i];
      if (v.roomId === roomId && v.online && v.door === 1) {
        count = count + 1;
      }
    }
    return count;
  }

  private roomOfflineCount(roomId: string): number {
    let count: number = 0;
    for (let i: number = 0; i < this.sensorViews.length; i++) {
      let v: SensorView = this.sensorViews[i];
      if (v.roomId === roomId && !v.online) {
        count = count + 1;
      }
    }
    return count;
  }

  private roomSubtitle(roomId: string): string {
    let total: number = this.roomSensorCount(roomId);
    if (total === 0) {
      return '点击添加门 / 窗传感器';
    }
    let open: number = this.roomOpenCount(roomId);
    let offline: number = this.roomOfflineCount(roomId);
    let text: string = `${open} 个开启`;
    if (offline > 0) {
      text = `${text} · ${offline} 个离线`;
    }
    return text;
  }

  private roomAccent(roomId: string): string {
    if (this.roomSensorCount(roomId) === 0) {
      return Theme.SUB;
    }
    if (this.roomOpenCount(roomId) > 0) {
      return Theme.WARN;
    }
    if (this.roomOfflineCount(roomId) > 0) {
      return Theme.SUB;
    }
    return Theme.OK;
  }

  private activeRoom(): RoomConfig | null {
    for (let i: number = 0; i < this.rooms.length; i++) {
      if (this.rooms[i].id === this.activeRoomId) {
        return this.rooms[i];
      }
    }
    return null;
  }

  private activeRoomName(): string {
    let room: RoomConfig | null = this.activeRoom();
    return room !== null ? room.name : '房间';
  }

  private activeRoomSensors(): SensorView[] {
    let list: SensorView[] = [];
    for (let i: number = 0; i < this.sensorViews.length; i++) {
      if (this.sensorViews[i].roomId === this.activeRoomId) {
        list.push(this.sensorViews[i]);
      }
    }
    return list;
  }

  private openAddRoom(): void {
    this.roomNameInput = '';
    this.showAddRoom = true;
  }

  private async addRoom(): Promise<void> {
    let name: string = this.roomNameInput.trim();
    if (name.length === 0) {
      this.toast('请输入房间名称');
      return;
    }
    for (let i: number = 0; i < this.rooms.length; i++) {
      if (this.rooms[i].name === name) {
        this.toast('房间名称已存在');
        return;
      }
    }
    let room: RoomConfig = { id: `${Date.now()}`, name: name, sensors: [] };
    let list: RoomConfig[] = this.rooms.concat([room]);
    await ConfigStore.saveRooms(list);
    this.rooms = list;
    this.showAddRoom = false;
    this.activeRoomId = room.id;
    this.sensorNameInput = '';
    this.sensorDeviceInput = '';
    this.sensorType = 'door';
    this.showRoomDetail = true;
    this.toast('房间已创建，可以添加传感器了');
  }

  private openRoom(roomId: string): void {
    this.activeRoomId = roomId;
    this.sensorNameInput = '';
    this.sensorDeviceInput = '';
    this.sensorType = 'door';
    this.showRoomDetail = true;
  }

  private async addSensor(): Promise<void> {
    let room: RoomConfig | null = this.activeRoom();
    if (room === null) {
      return;
    }
    let type: string = this.sensorType === 'window' ? 'window' : 'door';
    let name: string = this.sensorNameInput.trim();
    if (name.length === 0) {
      name = type === 'window' ? '窗传感器' : '门传感器';
      if (this.sensorNameExists(room, name)) {
        name = `${name} ${room.sensors.length + 1}`;
      }
    }
    if (this.sensorNameExists(room, name)) {
      this.toast('该房间已有同名传感器');
      return;
    }
    let no: number = Number.parseInt(this.sensorDeviceInput.trim());
    if (Number.isNaN(no) || no < 0) {
      this.toast('设备号需为 0 或正整数');
      return;
    }
    if (no === ConfigStore.getDeviceNo()) {
      this.toast('该设备号已被当前主机使用');
      return;
    }
    if (this.deviceNoExists(no)) {
      this.toast('该设备号已添加');
      return;
    }
    let cfg: RoomSensorConfig = {
      id: `${Date.now()}`,
      name: name,
      type: type,
      deviceNo: no
    };
    let list: RoomConfig[] = [];
    for (let i: number = 0; i < this.rooms.length; i++) {
      let r: RoomConfig = this.rooms[i];
      if (r.id === room.id) {
        list.push({ id: r.id, name: r.name, sensors: r.sensors.concat([cfg]) });
      } else {
        list.push(r);
      }
    }
    await ConfigStore.saveRooms(list);
    this.rooms = list;
    this.sensorViews = this.toSensorViews(list);
    this.sensorNameInput = '';
    this.sensorDeviceInput = '';
    this.toast('传感器已添加，正在读取状态...');
    await this.refreshSensors();
  }

  private sensorNameExists(room: RoomConfig, name: string): boolean {
    for (let i: number = 0; i < room.sensors.length; i++) {
      if (room.sensors[i].name === name) {
        return true;
      }
    }
    return false;
  }

  private deviceNoExists(deviceNo: number): boolean {
    for (let i: number = 0; i < this.rooms.length; i++) {
      for (let j: number = 0; j < this.rooms[i].sensors.length; j++) {
        if (this.rooms[i].sensors[j].deviceNo === deviceNo) {
          return true;
        }
      }
    }
    return false;
  }

  private async removeSensor(roomId: string, sensorId: string): Promise<void> {
    let list: RoomConfig[] = [];
    for (let i: number = 0; i < this.rooms.length; i++) {
      let r: RoomConfig = this.rooms[i];
      if (r.id !== roomId) {
        list.push(r);
        continue;
      }
      let sensors: RoomSensorConfig[] = [];
      for (let j: number = 0; j < r.sensors.length; j++) {
        if (r.sensors[j].id !== sensorId) {
          sensors.push(r.sensors[j]);
        }
      }
      list.push({ id: r.id, name: r.name, sensors: sensors });
    }
    await ConfigStore.saveRooms(list);
    this.rooms = list;
    this.sensorViews = this.toSensorViews(list);
    this.toast('传感器已移除');
  }

  private async removeRoom(roomId: string): Promise<void> {
    let list: RoomConfig[] = [];
    for (let i: number = 0; i < this.rooms.length; i++) {
      if (this.rooms[i].id !== roomId) {
        list.push(this.rooms[i]);
      }
    }
    await ConfigStore.saveRooms(list);
    this.rooms = list;
    this.sensorViews = this.toSensorViews(list);
    if (this.activeRoomId === roomId) {
      this.activeRoomId = '';
      this.showRoomDetail = false;
    }
    this.toast('房间已删除');
  }

  private tempAccent(): string {
    if (this.current.temp > Constants.TEMP_MAX || (this.current.temp < Constants.TEMP_MIN && this.current.temp !== 0)) {
      return Theme.WARN;
    }
    return Theme.PRIMARY;
  }

  private statusText(): string {
    return this.current.online ? '在线' : '离线';
  }

  private async saveConfig(): Promise<void> {
    let host: string = this.hostInput.trim();
    if (host.length === 0) {
      this.toast('请输入服务器 IP');
      return;
    }
    let port: number = Number.parseInt(this.portInput.trim());
    if (Number.isNaN(port) || port <= 0 || port > 65535) {
      this.toast('端口不合法（1-65535）');
      return;
    }
    let deviceNo: number = Number.parseInt(this.deviceInput.trim());
    if (Number.isNaN(deviceNo) || deviceNo < 0) {
      this.toast('设备号不合法');
      return;
    }
    try {
      await ConfigStore.save(host, port, deviceNo, ConfigStore.getPollMs());
      this.toast('已保存，正在重新连接...');
      this.showSettings = false;
      await HttpService.get().restart();
    } catch (e) {
      console.error(`配置保存失败: ${JSON.stringify(e)}`);
      this.toast('保存失败，请重试');
    }
  }

  @Builder
  settingsPanel() {
    Column({ space: 10 }) {
      Text('服务器设置')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TEXT)
        .width('100%')

      Row() {
        Text('IP')
          .fontSize(13)
          .fontColor(Theme.SUB)
          .width(56)
        TextInput({ placeholder: '如 10.19.81.90', text: this.hostInput })
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .backgroundColor(Theme.INPUT)
          .borderRadius(10)
          .onChange((v: string) => {
            this.hostInput = v;
          })
      }
      .width('100%')

      Row() {
        Text('端口')
          .fontSize(13)
          .fontColor(Theme.SUB)
          .width(56)
        TextInput({ placeholder: '如 8000', text: this.portInput })
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .backgroundColor(Theme.INPUT)
          .borderRadius(10)
          .type(InputType.Number)
          .onChange((v: string) => {
            this.portInput = v;
          })
      }
      .width('100%')

      Row() {
        Text('设备号')
          .fontSize(13)
          .fontColor(Theme.SUB)
          .width(56)
        TextInput({ placeholder: '如 0', text: this.deviceInput })
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .backgroundColor(Theme.INPUT)
          .borderRadius(10)
          .type(InputType.Number)
          .onChange((v: string) => {
            this.deviceInput = v;
          })
      }
      .width('100%')

      Row({ space: 10 }) {
        Button('保存并重连')
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .backgroundColor(Theme.PRIMARY)
          .borderRadius(10)
          .onClick(() => {
            this.saveConfig();
          })
        Button('立即刷新')
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .backgroundColor(Theme.PRIMARY_SOFT)
          .fontColor(Theme.PRIMARY)
          .borderRadius(10)
          .onClick(() => {
            HttpService.get().refresh();
            this.toast('已发起刷新');
          })
      }
      .width('100%')

      Text(ConfigStore.apiUrl(Constants.HTTP_HISTORY_LIMIT))
        .fontSize(11)
        .fontColor(Theme.SUB)
        .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Theme.CARD)
    .borderRadius(16)
    .border({ width: 1, color: Theme.HAIRLINE })
    .shadow({ radius: 14, color: Theme.SHADOW, offsetX: 0, offsetY: 4 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  statusBanner() {
    Column({ space: 4 }) {
      Row() {
        Column()
          .width(7)
          .height(7)
          .borderRadius(4)
          .backgroundColor(this.fetchOk ? Theme.OK : Theme.DANGER)
        Text(this.fetchMsg)
          .fontSize(12)
          .fontColor(this.fetchOk ? Theme.OK : Theme.DANGER)
          .margin({ left: 6 })
          .layoutWeight(1)
        Text(this.showSettings ? '收起设置' : '服务器设置')
          .fontSize(12)
          .fontColor(Theme.PRIMARY)
          .onClick(() => {
            this.showSettings = !this.showSettings;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        Text(this.lastUpdate > 0 ? `最后更新 ${DateUtil.time(this.lastUpdate)}` : '等待首次数据...')
          .fontSize(11)
          .fontColor(Theme.SUB)
          .layoutWeight(1)
        Text(this.showDebug ? '收起调试' : '接口调试')
          .fontSize(11)
          .fontColor(Theme.SUB)
          .onClick(() => {
            this.showDebug = !this.showDebug;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 9, bottom: 9 })
    .backgroundColor(Theme.GLASS)
    .borderRadius(12)
    .border({ width: 1, color: Theme.HAIRLINE })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  debugPanel() {
    Column({ space: 6 }) {
      Text('接口调试')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TEXT)
        .width('100%')
      Text(`请求地址：${ConfigStore.apiUrl(Constants.HTTP_HISTORY_LIMIT)}`)
        .fontSize(11)
        .fontColor(Theme.SUB)
        .width('100%')
      Text(`刷新次数：${this.revision}`)
        .fontSize(11)
        .fontColor(Theme.SUB)
        .width('100%')
      Text(`解析结果：门 ${this.current.door} / 存在 ${this.current.radarPresence} / 运动 ${this.current.radarMotion}`)
        .fontSize(11)
        .fontColor(Theme.TEXT)
        .width('100%')
      Text(`SOS ${this.current.sos} / 报警 ${this.current.alarm} / 上报时间 ${this.current.serverTs > 0 ? DateUtil.dateTime(this.current.serverTs) : '未知'}`)
        .fontSize(11)
        .fontColor(Theme.TEXT)
        .width('100%')
      Text('最近响应原文：')
        .fontSize(11)
        .fontColor(Theme.SUB)
        .width('100%')
        .margin({ top: 4 })
      Scroll() {
        Text(this.lastRaw.length > 0 ? this.lastRaw : '暂无响应')
          .fontSize(10)
          .fontColor(Theme.TEXT)
          .width('100%')
          .copyOption(CopyOptions.LocalDevice)
      }
      .width('100%')
      .height(150)
      .backgroundColor(Theme.CHIP)
      .borderRadius(8)
      .padding(6)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Theme.CARD)
    .borderRadius(16)
    .border({ width: 1, color: Theme.HAIRLINE })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  historyItem(rec: LatestRecord) {
    Row() {
      Column() {
        Text(DateUtil.time(rec.ts))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT)
        Text(rec.ts > 0 ? DateUtil.date(rec.ts) : '时间未知')
          .fontSize(11)
          .fontColor(Theme.SUB)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Row({ space: 10 }) {
        Text(`${rec.temp.toFixed(1)}℃`)
          .fontSize(13)
          .fontColor(Theme.PRIMARY)
        Text(`${rec.humi.toFixed(0)}%`)
          .fontSize(13)
          .fontColor(Theme.PRIMARY)
        Text(rec.door === 1 ? '门开' : '门关')
          .fontSize(12)
          .fontColor(rec.door === 1 ? Theme.WARN : Theme.SUB)
        Text(rec.radarPresence === 1 ? '有人' : '无人')
          .fontSize(12)
          .fontColor(rec.radarPresence === 1 ? Theme.OK : Theme.SUB)
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  roomCard(room: RoomConfig) {
    Column() {
      Row() {
        Stack() {
          AppIcon({ name: 'home', iconSize: 18, color: this.roomAccent(room.id), weight: 1.8 })
        }
        .width(32)
        .height(32)
        .borderRadius(10)
        .backgroundColor(Theme.alpha(this.roomAccent(room.id), 0.10))

        Text(room.name)
          .fontSize(13)
          .fontColor(Theme.SUB)
          .layoutWeight(1)
          .margin({ left: 9, right: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        AppIcon({ name: 'chevron', iconSize: 14, color: Theme.SUB })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        Text(`${this.roomSensorCount(room.id)}`)
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.roomAccent(room.id))
        Text('个传感器')
          .fontSize(11)
          .fontColor(Theme.SUB)
          .margin({ left: 3, bottom: 4 })
      }
      .width('100%')
      .margin({ top: 10 })
      .alignItems(VerticalAlign.Bottom)

      Text(this.roomSubtitle(room.id))
        .fontSize(11)
        .fontColor(Theme.SUB)
        .width('100%')
        .margin({ top: 5 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Theme.CARD)
    .borderRadius(16)
    .border({ width: 1, color: Theme.HAIRLINE })
    .shadow({ radius: 10, color: Theme.SHADOW, offsetX: 0, offsetY: 3 })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.openRoom(room.id);
    })
  }

  @Builder
  sensorRow(v: SensorView) {
    Row() {
      Stack() {
        AppIcon({
          name: this.sensorIcon(v),
          iconSize: 16,
          color: this.sensorAccent(v),
          weight: 1.8
        })
      }
      .width(30)
      .height(30)
      .borderRadius(9)
      .backgroundColor(Theme.alpha(this.sensorAccent(v), 0.10))

      Column({ space: 2 }) {
        Text(v.name)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.sensorSubtitle(v))
          .fontSize(10)
          .fontColor(Theme.SUB)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .margin({ left: 9, right: 6 })
      .alignItems(HorizontalAlign.Start)

      Text(this.sensorValue(v))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.sensorAccent(v))

      Stack() {
        AppIcon({ name: 'close', iconSize: 11, color: Theme.SUB })
      }
      .width(22)
      .height(22)
      .borderRadius(7)
      .backgroundColor(Theme.CARD)
      .margin({ left: 6 })
      .onClick(() => {
        this.removeSensor(v.roomId, v.id);
      })
    }
    .width('100%')
    .padding(10)
    .backgroundColor(Theme.CHIP)
    .borderRadius(12)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  typeChip(type: string, label: string) {
    Row({ space: 5 }) {
      AppIcon({
        name: type === 'window' ? 'window' : 'door',
        iconSize: 14,
        color: this.sensorType === type ? Theme.PRIMARY : Theme.SUB,
        weight: 1.8
      })
      Text(label)
        .fontSize(12)
        .fontColor(this.sensorType === type ? Theme.PRIMARY : Theme.SUB)
        .fontWeight(this.sensorType === type ? FontWeight.Medium : FontWeight.Normal)
    }
    .padding({ left: 10, right: 10, top: 7, bottom: 7 })
    .backgroundColor(this.sensorType === type ? Theme.PRIMARY_SOFT : Theme.CHIP)
    .borderRadius(9)
    .onClick(() => {
      this.sensorType = type;
    })
  }

  @Builder
  addRoomDialog() {
    Column() {
      Column({ space: 12 }) {
        Row() {
          Text('添加房间')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TEXT)
            .layoutWeight(1)
          Stack() {
            AppIcon({ name: 'close', iconSize: 14, color: Theme.SUB })
          }
          .width(30)
          .height(30)
          .borderRadius(9)
          .backgroundColor(Theme.CHIP)
          .onClick(() => {
            this.showAddRoom = false;
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text('先创建房间，再进入房间添加门 / 窗传感器，例如「客厅」「阳台」。')
          .fontSize(12)
          .fontColor(Theme.SUB)
          .width('100%')
          .lineHeight(18)

        Row() {
          Text('名称')
            .fontSize(13)
            .fontColor(Theme.SUB)
            .width(52)
          TextInput({ placeholder: '如：客厅', text: this.roomNameInput })
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .backgroundColor(Theme.INPUT)
            .borderRadius(10)
            .onChange((val: string) => {
              this.roomNameInput = val;
            })
        }
        .width('100%')

        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1)
            .height(42)
            .backgroundColor(Theme.CHIP)
            .fontColor(Theme.TEXT)
            .borderRadius(11)
            .onClick(() => {
              this.showAddRoom = false;
            })
          Button('创建')
            .layoutWeight(1)
            .height(42)
            .backgroundColor(Theme.PRIMARY)
            .borderRadius(11)
            .onClick(() => {
              this.addRoom();
            })
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .width('92%')
      .padding(20)
      .backgroundColor(Theme.CARD)
      .borderRadius(22)
      .border({ width: 1, color: Theme.HAIRLINE })
      .shadow({ radius: 28, color: Theme.SHADOW_STRONG, offsetX: 0, offsetY: 12 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(16, 32, 34, 0.32)')
    .backdropBlur(8)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  roomDetailDialog() {
    Column() {
      Column() {
        Row() {
          Column({ space: 2 }) {
            Text(this.activeRoomName())
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.TEXT)
            Text(`${this.activeRoomSensors().length} 个门 / 窗传感器`)
              .fontSize(11)
              .fontColor(Theme.SUB)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Stack() {
            AppIcon({ name: 'close', iconSize: 14, color: Theme.SUB })
          }
          .width(30)
          .height(30)
          .borderRadius(9)
          .backgroundColor(Theme.CHIP)
          .onClick(() => {
            this.showRoomDetail = false;
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Scroll() {
          Column({ space: 10 }) {
            if (this.activeRoomSensors().length === 0) {
              Text('这个房间还没有传感器')
                .fontSize(12)
                .fontColor(Theme.SUB)
                .width('100%')
                .textAlign(TextAlign.Center)
                .margin({ top: 16, bottom: 12 })
            } else {
              ForEach(this.activeRoomSensors(), (v: SensorView) => {
                this.sensorRow(v)
              }, (v: SensorView) => `${v.id}-${v.door}-${v.online ? 1 : 0}`)
            }

            Divider()
              .color(Theme.HAIRLINE)
              .margin({ top: 6, bottom: 2 })

            Text('添加传感器')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT)
              .width('100%')

            Row({ space: 8 }) {
              this.typeChip('door', '门传感器')
              this.typeChip('window', '窗传感器')
            }
            .width('100%')

            TextInput({ placeholder: '名称（选填，如：阳台门）', text: this.sensorNameInput })
              .width('100%')
              .height(40)
              .fontSize(14)
              .backgroundColor(Theme.INPUT)
              .borderRadius(10)
              .onChange((val: string) => {
                this.sensorNameInput = val;
              })

            TextInput({ placeholder: '设备号，如：1', text: this.sensorDeviceInput })
              .width('100%')
              .height(40)
              .fontSize(14)
              .type(InputType.Number)
              .backgroundColor(Theme.INPUT)
              .borderRadius(10)
              .onChange((val: string) => {
                this.sensorDeviceInput = val;
              })

            Button('添加到这个房间')
              .width('100%')
              .height(42)
              .fontSize(14)
              .backgroundColor(Theme.PRIMARY)
              .borderRadius(11)
              .onClick(() => {
                this.addSensor();
              })

            Text('删除房间')
              .fontSize(12)
              .fontColor(Theme.DANGER)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 6, bottom: 4 })
              .onClick(() => {
                this.removeRoom(this.activeRoomId);
              })
          }
          .width('100%')
          .padding({ top: 12 })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
      .width('92%')
      .height('82%')
      .padding(18)
      .backgroundColor(Theme.CARD)
      .borderRadius(22)
      .border({ width: 1, color: Theme.HAIRLINE })
      .shadow({ radius: 28, color: Theme.SHADOW_STRONG, offsetX: 0, offsetY: 12 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(16, 32, 34, 0.32)')
    .backdropBlur(8)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Stack() {
      Scroll() {
        Column({ space: 12 }) {
        // 顶部状态
        Row() {
          Column() {
            Text('居家守护')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.TEXT)
            Text(`设备号 ${this.current.deviceNo} · ${this.statusText()}`)
              .fontSize(12)
              .fontColor(Theme.SUB)
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Row() {
            Column()
              .width(8)
              .height(8)
              .borderRadius(4)
              .backgroundColor(this.current.online ? Theme.OK : Theme.SUB)
            Text(this.statusText())
              .fontSize(13)
              .fontColor(this.current.online ? Theme.OK : Theme.SUB)
              .margin({ left: 4 })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        this.statusBanner()

        if (this.showSettings) {
          this.settingsPanel()
        }

        if (this.showDebug) {
          this.debugPanel()
        }

        // 数据卡片
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          Column() {
            InfoCard({
              title: '室内温度',
              value: this.current.temp.toFixed(1),
              unit: '℃',
              icon: 'temp',
              accent: this.tempAccent()
            })
          }.width('48%').margin({ bottom: 12 })

          Column() {
            InfoCard({
              title: '室内湿度',
              value: this.current.humi.toFixed(0),
              unit: '%',
              icon: 'humidity',
              accent: Theme.PRIMARY
            })
          }.width('48%').margin({ bottom: 12 })

          Column() {
            InfoCard({
              title: '门窗状态',
              value: this.current.door === 1 ? '开启' : '关闭',
              icon: 'door',
              subtitle: this.current.door === 1 ? '请留意门窗是否关好' : '门窗处于关闭状态',
              accent: this.current.door === 1 ? Theme.WARN : Theme.OK
            })
          }.width('48%').margin({ bottom: 12 })

          Column() {
            InfoCard({
              title: '雷达存在',
              value: this.current.radarPresence === 1 ? '有人' : '无人',
              icon: 'presence',
              subtitle: '人体存在检测',
              accent: this.current.radarPresence === 1 ? Theme.OK : Theme.SUB
            })
          }.width('48%').margin({ bottom: 12 })

          Column() {
            InfoCard({
              title: '雷达运动',
              value: this.current.radarMotion === 1 ? '运动中' : '静止',
              icon: 'motion',
              subtitle: this.current.lastActive > 0 ? `最后活动 ${DateUtil.relative(this.current.lastActive)}` : '暂无活动',
              accent: this.current.radarMotion === 1 ? Theme.PRIMARY : Theme.SUB
            })
          }.width('48%').margin({ bottom: 12 })

          Column() {
            InfoCard({
              title: '紧急求助',
              value: this.current.sos === 1 ? '求助中' : '正常',
              icon: 'sos',
              subtitle: this.current.sos === 1 ? '老人已按下SOS按钮！' : '未触发',
              accent: this.current.sos === 1 ? Theme.DANGER : Theme.OK
            })
          }.width('48%').margin({ bottom: 12 })

          Column() {
            InfoCard({
              title: '报警状态',
              value: this.current.alarm === 1 ? (this.current.alarmType.length > 0 ? this.current.alarmType : '报警中') : '正常',
              icon: 'warning',
              subtitle: this.current.alarm === 1 ? '设备已触发报警' : '无报警',
              accent: this.current.alarm === 1 ? Theme.DANGER : Theme.OK
            })
          }.width('48%').margin({ bottom: 12 })

          Column() {
            InfoCard({
              title: '设备状态',
              value: this.statusText(),
              icon: 'signal',
              subtitle: this.current.serverTs > 0
                ? `最近上报 ${DateUtil.time(this.current.serverTs)}`
                : (this.lastUpdate > 0 ? `最后拉取 ${DateUtil.time(this.lastUpdate)}` : '等待数据...'),
              accent: this.current.online ? Theme.OK : Theme.DANGER
            })
          }.width('48%').margin({ bottom: 12 })

          Row() {
            Text('房间')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT)
            Text('门 / 窗传感器')
              .fontSize(11)
              .fontColor(Theme.SUB)
              .margin({ left: 6 })
          }
          .width('100%')
          .margin({ top: 2, bottom: 2 })
          .alignItems(VerticalAlign.Bottom)

          ForEach(this.rooms, (room: RoomConfig) => {
            Column() {
              this.roomCard(room)
            }
            .width('48%')
            .margin({ bottom: 12 })
          }, (room: RoomConfig) => `${room.id}-${this.roomSensorCount(room.id)}-${this.roomOpenCount(room.id)}`)

          Row() {
            Stack() {
              AppIcon({ name: 'plus', iconSize: 20, color: Theme.PRIMARY })
            }
            .width(36)
            .height(36)
            .borderRadius(11)
            .backgroundColor(Theme.PRIMARY_SOFT)

            Column({ space: 3 }) {
              Text('添加房间')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.TEXT)
              Text('按房间管理门 / 窗传感器')
                .fontSize(11)
                .fontColor(Theme.SUB)
            }
            .layoutWeight(1)
            .margin({ left: 10 })
            .alignItems(HorizontalAlign.Start)

            AppIcon({ name: 'chevron', iconSize: 16, color: Theme.SUB })
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Theme.CARD)
          .borderRadius(16)
          .border({ width: 1, color: Theme.BORDER, style: BorderStyle.Dashed })
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.openAddRoom();
          })
        }
        .width('100%')

        // SOS 醒目提示
        if (this.current.sos === 1) {
          Row() {
            Stack() {
              AppIcon({ name: 'sos', iconSize: 21, color: '#FFFFFF', weight: 1.9 })
            }
            .width(36)
            .height(36)
            .borderRadius(11)
            .backgroundColor(Theme.alpha('#FFFFFF', 0.16))

            Text('检测到紧急求助信号，请立即处理！')
              .fontSize(15)
              .fontColor('#FFFFFF')
              .fontWeight(FontWeight.Bold)
              .margin({ left: 10 })
              .layoutWeight(1)
          }
          .width('100%')
          .padding(15)
          .backgroundColor(Theme.DANGER)
          .borderRadius(16)
          .shadow({ radius: 16, color: Theme.alpha(Theme.DANGER, 0.24), offsetX: 0, offsetY: 6 })
          .alignItems(VerticalAlign.Center)
        }

        // 报警醒目提示
        if (this.current.alarm === 1) {
          Row() {
            Stack() {
              AppIcon({ name: 'warning', iconSize: 21, color: '#FFFFFF', weight: 1.9 })
            }
            .width(36)
            .height(36)
            .borderRadius(11)
            .backgroundColor(Theme.alpha('#FFFFFF', 0.16))

            Text(this.current.alarmType.length > 0
              ? `设备报警：${this.current.alarmType}`
              : '设备报警，请立即处理！')
              .fontSize(15)
              .fontColor('#FFFFFF')
              .fontWeight(FontWeight.Bold)
              .margin({ left: 10 })
              .layoutWeight(1)
          }
          .width('100%')
          .padding(15)
          .backgroundColor(Theme.DANGER)
          .borderRadius(16)
          .shadow({ radius: 16, color: Theme.alpha(Theme.DANGER, 0.24), offsetX: 0, offsetY: 6 })
          .alignItems(VerticalAlign.Center)
        }

        // 最近上报历史
        Column() {
          Row() {
            Text('最近上报记录')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT)
              .layoutWeight(1)
            Text(`最近 ${this.history.length} 条`)
              .fontSize(12)
              .fontColor(Theme.SUB)
          }
          .width('100%')

          if (this.history.length === 0) {
            Text('暂无历史记录')
              .fontSize(13)
              .fontColor(Theme.SUB)
              .width('100%')
              .margin({ top: 10 })
          } else {
            ForEach(this.history, (rec: LatestRecord) => {
              this.historyItem(rec)
            }, (rec: LatestRecord, index: number) => `${rec.id}-${index}`)
          }
        }
        .width('100%')
        .padding(14)
        .backgroundColor(Theme.CARD)
        .borderRadius(16)
        .border({ width: 1, color: Theme.HAIRLINE })
        .shadow({ radius: 14, color: Theme.SHADOW, offsetX: 0, offsetY: 4 })
        .alignItems(HorizontalAlign.Start)
      }
      .padding(16)
      .width('100%')
    }
    .backgroundColor(Theme.BG)
    .width('100%')
    .height('100%')

      if (this.showAddRoom) {
        this.addRoomDialog()
      }

      if (this.showRoomDetail) {
        this.roomDetailDialog()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
  }
}
