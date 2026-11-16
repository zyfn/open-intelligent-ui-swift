import { memo, useMemo } from 'react';
import Svg, { Ellipse, Path, Rect } from 'react-native-svg';
import iconCatalog from '../../../../../Sources/SwiftOpenUI/Resources/lucide-icons.json';
import { useOpenUITheme } from '../theme';

type Shape = { commands?: (string | number)[][]; ellipse?: number[]; rect?: number[]; fill: boolean };
const catalog = iconCatalog as unknown as { fallbacks: Record<string, string>; icons: Record<string, Shape[]> };

/** Draw the repository's pinned Lucide resource; no fonts, network or second icon set. */
export const NativeIcon = memo(function NativeIcon({ name, category, size = 20, color, accessibilityLabel }: {
  name: string; category?: string; size?: number; color?: string; accessibilityLabel?: string;
}) {
  const theme = useOpenUITheme();
  const normalized = name.trim().toLowerCase();
  const categoryName = category?.trim().toLowerCase() ?? '';
  const fallback = Object.hasOwn(catalog.fallbacks, categoryName) ? catalog.fallbacks[categoryName] : 'circle-help';
  const shapes = Object.hasOwn(catalog.icons, normalized) ? catalog.icons[normalized]
    : Object.hasOwn(catalog.icons, fallback) ? catalog.icons[fallback] : catalog.icons['circle-help'];
  const paths = useMemo(() => shapes.map(shape => ({ ...shape,
    d: shape.commands?.map(command => command.join(' ')).join(' '),
  })), [shapes]);
  if (!normalized) return null;
  const ink = color ?? theme.ink;
  return <Svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={ink}
    strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0 }}
    accessible={Boolean(accessibilityLabel)} accessibilityRole="image" accessibilityLabel={accessibilityLabel}
    accessibilityElementsHidden={!accessibilityLabel} importantForAccessibility={accessibilityLabel ? 'yes' : 'no'}>
    {paths.map((shape, index) => {
      const fill = shape.fill ? ink : 'none';
      if (shape.ellipse) {
        const [cx, cy, rx, ry] = shape.ellipse;
        return <Ellipse key={index} cx={cx} cy={cy} rx={rx} ry={ry} fill={fill} />;
      }
      if (shape.rect) {
        const [x, y, width, height, rx, ry] = shape.rect;
        return <Rect key={index} x={x} y={y} width={width} height={height} rx={rx} ry={ry} fill={fill} />;
      }
      return <Path key={index} d={shape.d} fill={fill} />;
    })}
  </Svg>;
});
