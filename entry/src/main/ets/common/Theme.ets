/**
 * 应用配色与尺寸。
 *
 * 视觉基调：中性浅灰底 + 半透明“毛玻璃”卡片 + 1px 发丝描边，
 * 主色只用于图标、关键数值与按钮，避免大面积高饱和色块。
 * 所有色值都集中在这里，方便统一调整。
 */
export class Theme {
  // 主色（低饱和深青，替代原来偏亮的 teal）
  static readonly PRIMARY: string = '#14776E';
  static readonly PRIMARY_DARK: string = '#0B5B54';
  static readonly PRIMARY_SOFT: string = '#E4F0EE';

  // 背景与玻璃层
  static readonly BG: string = '#F3F5F6';
  static readonly CARD: string = 'rgba(255, 255, 255, 0.88)';
  static readonly CARD_SOLID: string = '#FFFFFF';
  static readonly GLASS: string = 'rgba(255, 255, 255, 0.62)';
  static readonly CHIP: string = 'rgba(20, 60, 60, 0.045)';
  static readonly INPUT: string = 'rgba(20, 60, 60, 0.045)';

  // 文字与线条
  static readonly TEXT: string = '#152523';
  static readonly SUB: string = '#788785';
  static readonly HAIRLINE: string = 'rgba(18, 44, 48, 0.07)';
  static readonly BORDER: string = '#E6EBEA';

  // 语义色（同样降低饱和度）
  static readonly OK: string = '#2F7D5C';
  static readonly OK_SOFT: string = '#E7F2EC';
  static readonly WARN: string = '#B4762A';
  static readonly WARN_SOFT: string = '#F8EFE3';
  static readonly DANGER: string = '#B8453F';
  static readonly DANGER_SOFT: string = '#F8E9E7';

  // 阴影
  static readonly SHADOW: string = 'rgba(20, 48, 52, 0.07)';
  static readonly SHADOW_STRONG: string = 'rgba(20, 48, 52, 0.12)';

  /** 把 #RRGGBB 转成带透明度的 rgba()，用于图标底色等浅色块 */
  static alpha(color: string, opacity: number): string {
    if (color.length !== 7 || color.charAt(0) !== '#') {
      return color;
    }
    let r: number = Number.parseInt(color.substring(1, 3), 16);
    let g: number = Number.parseInt(color.substring(3, 5), 16);
    let b: number = Number.parseInt(color.substring(5, 7), 16);
    return `rgba(${r}, ${g}, ${b}, ${opacity})`;
  }
}
