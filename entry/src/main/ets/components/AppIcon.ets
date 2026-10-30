import { Theme } from '../common/Theme';

/**
 * 统一线性图标组件（24 × 24 网格，圆角线帽，单色）。
 *
 * 用矢量 Path 代替 emoji：颜色可由父级控制，缩放不失真，
 * 在深色按钮、浅色卡片、底部导航里都能保持同一套语言。
 *
 * 用法：
 *   AppIcon({ name: 'home', iconSize: 20, color: Theme.PRIMARY })
 *   AppIcon({ name: 'stop', iconSize: 16, color: '#FFFFFF', filled: true })
 */
@Component
export struct AppIcon {
  @Prop name: string = 'dot';
  // 注意：不能命名为 size，size() 是 CustomComponent 的通用布局属性，会与基类冲突
  @Prop iconSize: number = 20;
  @Prop color: string = Theme.TEXT;
  @Prop weight: number = 1.7;
  @Prop filled: boolean = false;

  private commands(): string {
    switch (this.name) {
      case 'home':
        return 'M4 10.6 L12 3.8 L20 10.6 M6.4 9.2 L6.4 20.2 L17.6 20.2 L17.6 9.2 ' +
          'M10 20.2 L10 14.4 L14 14.4 L14 20.2';
      case 'report':
        return 'M4.2 20 L19.8 20 M7.2 20 L7.2 12.8 M12 20 L12 7.4 M16.8 20 L16.8 10.4';
      case 'bell':
        return 'M12 4.2 C8.9 4.2 6.9 6.5 6.9 9.6 L6.9 13.1 L5.2 16.3 L18.8 16.3 ' +
          'L17.1 13.1 L17.1 9.6 C17.1 6.5 15.1 4.2 12 4.2 Z ' +
          'M9.9 18.9 C10.4 19.8 11.1 20.3 12 20.3 C12.9 20.3 13.6 19.8 14.1 18.9';
      case 'chat':
        return 'M5 5.6 L19 5.6 C19.9 5.6 20.6 6.3 20.6 7.2 L20.6 15.2 C20.6 16.1 19.9 16.8 19 16.8 ' +
          'L11.4 16.8 L7.2 20.2 L7.2 16.8 L5 16.8 C4.1 16.8 3.4 16.1 3.4 15.2 L3.4 7.2 ' +
          'C3.4 6.3 4.1 5.6 5 5.6 Z M8 10.6 L8 10.8 M12 10.6 L12 10.8 M16 10.6 L16 10.8';
      case 'ai':
        return 'M11.2 3.6 C11.9 8.1 13.5 9.7 18 10.4 C13.5 11.1 11.9 12.7 11.2 17.2 ' +
          'C10.5 12.7 8.9 11.1 4.4 10.4 C8.9 9.7 10.5 8.1 11.2 3.6 Z ' +
          'M17.9 15.4 C18.1 17.2 18.7 17.8 20.5 18 C18.7 18.2 18.1 18.8 17.9 20.6 ' +
          'C17.7 18.8 17.1 18.2 15.3 18 C17.1 17.8 17.7 17.2 17.9 15.4 Z';
      case 'doc':
        return 'M6.4 3.6 L14.6 3.6 L18.4 7.4 L18.4 20.4 L6.4 20.4 Z ' +
          'M14.6 3.6 L14.6 7.4 L18.4 7.4 M9.2 12.2 L15.6 12.2 M9.2 16 L15.6 16';
      case 'settings':
        return 'M3.8 6.6 L7.4 6.6 M10.6 6.6 L20.2 6.6 M3.8 12 L12.4 12 M15.6 12 L20.2 12 ' +
          'M3.8 17.4 L6.4 17.4 M9.6 17.4 L20.2 17.4 ' +
          this.circle(9, 6.6, 1.6) + ' ' +
          this.circle(14, 12, 1.6) + ' ' +
          this.circle(8, 17.4, 1.6);
      case 'temp':
        return 'M10.8 14 L10.8 6.2 C10.8 5 11.4 4.1 12 4.1 C12.6 4.1 13.2 5 13.2 6.2 L13.2 14 ' +
          'M12 13 L12 8.6 ' + this.circle(12, 17.5, 3.9);
      case 'humidity':
        return 'M12 3.6 C12 3.6 5.8 10.4 5.8 14.7 C5.8 18.2 8.6 20.8 12 20.8 ' +
          'C15.4 20.8 18.2 18.2 18.2 14.7 C18.2 10.4 12 3.6 12 3.6 Z';
      case 'door':
        return 'M6.8 3.6 L17.2 3.6 L17.2 20.4 L6.8 20.4 Z ' + this.circle(14.1, 12.1, 0.9);
      case 'window':
        return 'M5.2 4.6 L18.8 4.6 L18.8 19.4 L5.2 19.4 Z M5.2 12 L18.8 12 M12 4.6 L12 19.4';
      case 'presence':
        return this.circle(12, 6.8, 2.7) + ' ' +
          'M5.6 20.4 C5.6 16.2 8 13.6 12 13.6 C16 13.6 18.4 16.2 18.4 20.4';
      case 'motion':
        return 'M3.4 12 L7.2 12 L9.6 6.6 L13.6 17.4 L16 12 L20.6 12';
      case 'sos':
        return this.circle(12, 12, 8.4) + ' M12 7.4 L12 13 M12 16.4 L12 16.6';
      case 'warning':
        return 'M12 3.8 L21 19.6 L3 19.6 Z M12 9.2 L12 14 M12 16.8 L12 17';
      case 'signal':
        return 'M3.4 9 C8.2 4.4 15.8 4.4 20.6 9 M6.6 12.4 C10 9.2 14 9.2 17.4 12.4 ' +
          'M9.8 15.8 C11.2 14.4 12.8 14.4 14.2 15.8 M12 19.2 L12 19.4';
      case 'close':
        return 'M6.4 6.4 L17.6 17.6 M17.6 6.4 L6.4 17.6';
      case 'check':
        return 'M4.8 12.4 L9.6 17.2 L19.2 6.8';
      case 'chevron':
        return 'M7 10 L12 15 L17 10';
      case 'send':
        return 'M20.4 3.6 L3.4 10.4 L10.4 13.6 L13.6 20.4 L20.4 3.6 Z M10.4 13.6 L20.4 3.6';
      case 'stop':
        return 'M7.4 5.8 L16.6 5.8 C17.5 5.8 18.2 6.5 18.2 7.4 L18.2 16.6 ' +
          'C18.2 17.5 17.5 18.2 16.6 18.2 L7.4 18.2 C6.5 18.2 5.8 17.5 5.8 16.6 ' +
          'L5.8 7.4 C5.8 6.5 6.5 5.8 7.4 5.8 Z';
      case 'copy':
        return 'M8.6 8.6 L19 8.6 L19 19 L8.6 19 Z M5 15.6 L5 5 L15.6 5';
      case 'retry':
        return 'M20 12 C20 7.6 16.4 4 12 4 C8.9 4 6.2 5.8 5 8.4 ' +
          'M5 8.4 L5 4.4 M5 8.4 L9 8.4 ' +
          'M4 12 C4 16.4 7.6 20 12 20 C15.1 20 17.8 18.2 19 15.6 ' +
          'M19 15.6 L19 19.6 M19 15.6 L15 15.6';
      case 'trash':
        return 'M4.6 6.8 L19.4 6.8 M9.2 6.8 L9.2 4.4 L14.8 4.4 L14.8 6.8 ' +
          'M6.8 6.8 L7.8 20 L16.2 20 L17.2 6.8 M10.4 10.6 L10.4 16.2 M13.6 10.6 L13.6 16.2';
      case 'plus':
        return 'M12 5 L12 19 M5 12 L19 12';
      case 'usb':
        return 'M12 20.4 L12 5 M12 8.8 L8.2 11.8 L8.2 14.6 M12 7.2 L15.8 10.2 L15.8 13';
      case 'shield':
        return 'M12 3.6 L19.4 6.6 L19.4 12 C19.4 16.4 16.4 19.8 12 20.8 ' +
          'C7.6 19.8 4.6 16.4 4.6 12 L4.6 6.6 Z';
      case 'dot':
        return this.circle(12, 12, 2);
      default:
        return this.circle(12, 12, 2);
    }
  }

  /** 用三次贝塞尔逼近圆，避免部分设备对 Path 的 A（arc）指令解析失败 */
  private circle(cx: number, cy: number, r: number): string {
    let k: number = r * 0.55228475;
    return `M${cx + r} ${cy} ` +
      `C${cx + r} ${cy + k} ${cx + k} ${cy + r} ${cx} ${cy + r} ` +
      `C${cx - k} ${cy + r} ${cx - r} ${cy + k} ${cx - r} ${cy} ` +
      `C${cx - r} ${cy - k} ${cx - k} ${cy - r} ${cx} ${cy - r} ` +
      `C${cx + k} ${cy - r} ${cx + r} ${cy - k} ${cx + r} ${cy} Z`;
  }

  private scaleNumber(raw: string, factor: number): string {
    let value: number = Number.parseFloat(raw) * factor;
    return `${Math.round(value * 100) / 100}`;
  }

  /**
   * Path 的 commands 以 px 为单位，而组件尺寸是 vp。
   * 这里按当前屏幕密度换算，保证 24 网格的图标刚好铺满 iconSize。
   */
  private scaledCommands(): string {
    let raw: string = this.commands();
    let factor: number = this.getUIContext().vp2px(1) * this.iconSize / 24;
    let out: string = '';
    let token: string = '';
    for (let i: number = 0; i < raw.length; i++) {
      let c: string = raw.charAt(i);
      let isDigit: boolean = c >= '0' && c <= '9';
      let isDot: boolean = c === '.';
      let isMinus: boolean = c === '-' && token.length === 0;
      if (isDigit || isDot || isMinus) {
        token += c;
      } else {
        if (token.length > 0) {
          out += this.scaleNumber(token, factor);
          token = '';
        }
        out += c;
      }
    }
    if (token.length > 0) {
      out += this.scaleNumber(token, factor);
    }
    return out;
  }

  build() {
    Path()
      .commands(this.scaledCommands())
      .width(this.iconSize)
      .height(this.iconSize)
      .fill(this.filled ? this.color : Color.Transparent)
      .stroke(this.filled ? Color.Transparent : this.color)
      .strokeWidth(this.weight)
      .strokeLineCap(LineCapStyle.Round)
      .strokeLineJoin(LineJoinStyle.Round)
  }
}
