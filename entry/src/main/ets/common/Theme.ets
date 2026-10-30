/**
 * 应用配色与尺寸。
 *
 * 视觉基调：浅灰纯色底 + 白色卡片 + 1px 发丝描边，
 * 主色只用于图标与关键数值，整体保持简洁、克制。
 */
export class Theme {
  // 主色（低饱和深青）
  static readonly PRIMARY: string = '#14776E';
  static readonly PRIMARY_DARK: string = '#0B5B54';
  static readonly PRIMARY_SOFT: string = '#E4F0EE';

  // 背景与卡片（纯色体系，不使用半透明叠色）
  static readonly BG: string = '#F4F5F6';
  static readonly CARD: string = '#FFFFFF';
  static readonly CARD_SOLID: string = '#FFFFFF';
  static readonly GLASS: string = '#FFFFFF';
  static readonly CHIP: string = '#F1F4F3';
  static readonly INPUT: string = '#F4F6F6';

  // 文字与线条
  static readonly TEXT: string = '#152523';
  static readonly SUB: string = '#7A8886';
  static readonly HAIRLINE: string = '#EBEEEE';
  static readonly BORDER: string = '#E6EBEA';

  // 语义色
  static readonly OK: string = '#2F7D5C';
  static readonly OK_SOFT: string = '#E7F2EC';
  static readonly WARN: string = '#B4762A';
  static readonly WARN_SOFT: string = '#F8EFE3';
  static readonly DANGER: string = '#B8453F';
  static readonly DANGER_SOFT: string = '#F8E9E7';

  // 阴影
  static readonly SHADOW: string = 'rgba(17, 40, 44, 0.05)';
  static readonly SHADOW_STRONG: string = 'rgba(17, 40, 44, 0.12)';

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
