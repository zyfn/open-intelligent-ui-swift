import { useId, useMemo, useState, type ReactNode } from 'react';
import { Modal, Pressable, ScrollView, Text, View } from 'react-native';
import Svg, { Circle, ClipPath, Defs, G, Line, Path, Rect, Text as SvgText } from 'react-native-svg';
import { useIsStreaming, type ComponentRenderer } from '@openuidev/react-lang';
import { useDocumentInteraction } from '../../runtime/interaction';
import { useOpenUITheme, type NativeTheme } from '../theme';
import { useFieldGuard } from './useNativeField';
import { chartArcPath, chartDomain, chartLinePath, chartSectorPath, chartTick, polarPoint,
  positiveFractions, project, type ChartDomain, type ChartPoint, type ChartSeries } from './chartGeometry';

type Kind = 'BarChart' | 'LineChart' | 'AreaChart' | 'RadarChart' | 'HorizontalBarChart'
  | 'PieChart' | 'RadialChart' | 'SingleStackedBarChart' | 'ScatterChart';
type Series = ChartSeries & { color: number };
type ScatterPoint = { x: number; y: number; z?: number; id: string; series: number };
type Entry = { id: string; text: string; color: number };
type Data = { labels: string[]; series: Series[]; values: number[]; scatter: ScatterPoint[];
  names: string[]; entries: Entry[]; issue?: string; negative: boolean };
const titles: Record<Kind, string> = {
  BarChart: '柱状图', LineChart: '折线图', AreaChart: '面积图', RadarChart: '雷达图',
  HorizontalBarChart: '横向柱状图', PieChart: '饼图', RadialChart: '径向条形图',
  SingleStackedBarChart: '单条堆叠图', ScatterChart: '散点图',
};
const PAGE_SIZE = 12;
const MAX_PLOT_POINTS = 2_000;
const noHiddenSeries: ReadonlySet<number> = new Set();
const array = (value: unknown): unknown[] => Array.isArray(value) ? value : [];
const text = (value: unknown) => typeof value === 'string' ? value : '';
const number = (value: unknown): value is number => typeof value === 'number' && Number.isFinite(value);
function properties(value: unknown, type: string): Record<string, unknown> | undefined {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return;
  const item = value as Record<string, unknown>;
  if (item.type === 'element') {
    if (item.typeName !== type || !item.props || typeof item.props !== 'object') return;
    return item.props as Record<string, unknown>;
  }
  return item;
}

/** Typed helper nodes are data. They are never mounted as child chart controls. */
function readData(kind: Kind, props: Record<string, unknown>): Data {
  const result: Data = { labels: [], series: [], values: [], scatter: [], names: [], entries: [], negative: false };
  const invalid = () => { result.issue = '数据包含无效数值，或标签与数值数量不一致。'; };
  if (kind === 'ScatterChart') {
    for (const [series, value] of array(props.datasets).entries()) {
      const source = properties(value, 'ScatterSeries');
      if (!source || typeof source.name !== 'string' || !Array.isArray(source.points)) { invalid(); continue; }
      result.names.push(source.name);
      for (const [index, raw] of source.points.entries()) {
        const point = properties(raw, 'Point');
        if (!point || !number(point.x) || !number(point.y) || (point.z != null && !number(point.z))) { invalid(); continue; }
        const id = `point:${series}:${index}`;
        const z = number(point.z) ? point.z : undefined;
        result.scatter.push({ x: point.x, y: point.y, z, series, id });
        result.entries.push({ id, color: series,
          text: `${source.name} · ${index + 1}：x ${point.x}，y ${point.y}${z === undefined ? '' : `，z ${z}`}` });
        if (point.x < 0 || point.y < 0 || (z ?? 0) < 0) result.negative = true;
      }
    }
    return result;
  }
  const labels = array(props.labels);
  const polar = kind === 'PieChart' || kind === 'RadialChart' || kind === 'SingleStackedBarChart';
  // Slice is also an upstream data helper; support the documented helper shape
  // when a stream supplies helper nodes before a separate values array.
  if (polar && !array(props.values).length && labels.length && labels.every(value => !!properties(value, 'Slice'))) {
    for (const [index, value] of labels.entries()) {
      const slice = properties(value, 'Slice')!;
      if (typeof slice.category !== 'string' || !number(slice.value)) { invalid(); continue; }
      result.labels.push(slice.category); result.values.push(slice.value);
      result.entries.push({ id: `slice:${index}`, color: index, text: `${slice.category}：${slice.value}` });
    }
  } else {
    result.labels = labels.map(value => { if (typeof value !== 'string') invalid(); return text(value); });
    if (polar) {
      const values = array(props.values);
      if (values.length !== result.labels.length) invalid();
      for (const [index, value] of values.entries()) {
        if (!number(value)) { invalid(); continue; }
        result.values.push(value);
        result.entries.push({ id: `slice:${index}`, color: index,
          text: `${result.labels[index] ?? `第 ${index + 1} 项`}：${value}` });
      }
    } else {
      const keyed: Record<string, Series> = Object.create(null);
      const colors = new Map<string, number>();
      for (const value of array(props.series)) {
        const source = properties(value, 'Series');
        if (!source || typeof source.category !== 'string' || !Array.isArray(source.values)) { invalid(); continue; }
        if (!colors.has(source.category)) colors.set(source.category, colors.size);
        const values = source.values;
        if (values.length !== result.labels.length || !values.every(number)) { invalid(); }
        if (!values.every(number)) continue;
        keyed[source.category] = { name: source.category, values, color: colors.get(source.category)! };
      }
      // Match upstream keyed-series behavior: the final duplicate wins and
      // integer-like category keys retain ECMAScript object key ordering.
      result.series = Object.values(keyed);
      result.names = result.series.map(series => series.name);
      for (const [series, row] of result.series.entries()) {
        for (const [index, value] of row.values.entries()) {
          result.entries.push({ id: `series:${series}:${index}`, color: row.color,
            text: `${result.labels[index] ?? `第 ${index + 1} 项`} · ${row.name}：${value}` });
          if (value < 0) result.negative = true;
        }
      }
    }
  }
  if (polar) {
    result.names = result.labels;
    result.negative = result.values.some(value => value < 0);
  }
  return result;
}

const paletteFor = (theme: NativeTheme) => [theme.accent, '#4F8CD2', '#B28C42', '#9C72CF', '#D17991', '#4CA0A8', '#85A05C', '#D28A61'];
const shortened = (value: string, count = 12) => Array.from(value).length > count
  ? Array.from(value).slice(0, count - 1).join('') + '…' : value;
const dataColor = (palette: readonly string[], index: number) => palette[index % palette.length];

function ChartControl({ label, onPress, disabled = false, selected }: {
  label: string; onPress: () => void; disabled?: boolean; selected?: boolean;
}) {
  const theme = useOpenUITheme();
  return <Pressable accessibilityRole="button" accessibilityLabel={label}
    accessibilityState={{ disabled, selected }} disabled={disabled} onPress={onPress}
    style={({ pressed }) => ({ minHeight: theme.controlMinHeight, justifyContent: 'center',
      paddingHorizontal: 12, paddingVertical: 8, borderRadius: 10, borderWidth: 1,
      borderColor: theme.border, backgroundColor: pressed ? theme.surfaceMuted : theme.surface,
      opacity: disabled ? 0.5 : 1, minWidth: 0, flexShrink: 1 })}>
    <Text style={{ color: theme.accent, fontSize: 14, lineHeight: 21, flexShrink: 1 }}>{label}</Text>
  </Pressable>;
}

type PlotProps = { kind: Kind; data: Data; width: number; height: number; variant: string; semi: boolean;
  hidden: ReadonlySet<number>; selected?: string; select: (id: string) => void;
  palette: readonly string[]; theme: NativeTheme; clipId: string };

function ticks(domain: ChartDomain): number[] {
  // Weighted endpoints avoid high-low overflowing for a mixed ±MAX_VALUE domain.
  return [...new Set(Array.from({ length: 5 }, (_, index) => domain.low * (1 - index / 4) + domain.high * index / 4))];
}

function CartesianPlot({ kind, data, width, height, variant, hidden, selected, select, palette, theme, clipId }: PlotProps) {
  const horizontal = kind === 'HorizontalBarChart';
  const bars = kind === 'BarChart' || horizontal;
  const stacked = bars && variant === 'stacked';
  const visible = data.series.map((row, index) => ({ row, index })).filter(item => !hidden.has(item.index));
  const domain = chartDomain(visible.map(item => item.row), data.labels.length, stacked);
  if (!domain) return null;
  const left = horizontal ? Math.min(width * 0.32, 112) : 56;
  const right = width - 16;
  const top = 18;
  const bottom = height - 36;
  const pitch = (horizontal ? bottom - top : right - left) / Math.max(1, data.labels.length);
  const valuePosition = (value: number) => project(value, domain, horizontal ? left : bottom, horizontal ? right : top);
  const labels: ReactNode[] = [];
  const shapes: ReactNode[] = [];
  for (const value of ticks(domain)) {
    const position = valuePosition(value);
    labels.push(<G key={`tick:${value}`}>
      <Line x1={horizontal ? position : left} x2={horizontal ? position : right}
        y1={horizontal ? top : position} y2={horizontal ? bottom : position}
        stroke={Math.abs(value) < 1e-10 ? theme.muted : theme.border} strokeWidth={0.7} />
      <SvgText x={horizontal ? position : left - 7} y={horizontal ? bottom + 18 : position + 4}
        fontSize={11} fill={theme.muted} textAnchor={horizontal ? 'middle' : 'end'}>{chartTick(value)}</SvgText>
    </G>);
  }
  const stride = Math.max(1, Math.ceil(data.labels.length / Math.max(1, Math.floor((horizontal ? bottom - top : right - left) / (horizontal ? 30 : 64)))));
  for (let index = 0; index < data.labels.length; index += stride) {
    const category = (horizontal ? top : left) + pitch * (index + 0.5);
    labels.push(<SvgText key={`category:${index}`} x={horizontal ? left - 8 : category}
      y={horizontal ? category + 4 : bottom + 19} fill={theme.muted} fontSize={11}
      textAnchor={horizontal ? 'end' : 'middle'}>{shortened(data.labels[index], horizontal ? 12 : 8)}</SvgText>);
  }
  if (bars) {
    for (let index = 0; index < data.labels.length; index++) {
      let positive = 0; let negative = 0;
      for (const [slot, { row, index: series }] of visible.entries()) {
        const value = row.values[index];
        const base = stacked ? value >= 0 ? positive : negative : 0;
        const first = valuePosition(base); const last = valuePosition(base + value);
        const breadth = pitch * 0.72 / Math.max(1, stacked ? 1 : visible.length);
        const category = (horizontal ? top : left) + pitch * (index + 0.14) + (stacked ? 0 : slot * breadth);
        const id = `series:${series}:${index}`;
        shapes.push(<Rect key={id} testID={`chart-bar-${series}-${index}`}
          x={horizontal ? Math.min(first, last) : category + (stacked ? 0 : 1)}
          y={horizontal ? category + (stacked ? 0 : 1) : Math.min(first, last)}
          width={horizontal ? Math.abs(last - first) : Math.max(0.5, breadth - (stacked ? 0 : 2))}
          height={horizontal ? Math.max(0.5, breadth - (stacked ? 0 : 2)) : Math.abs(last - first)}
          rx={stacked ? 0 : 2} fill={dataColor(palette, row.color)} opacity={selected && selected !== id ? 0.45 : 1}
          onPress={() => select(id)} />);
        if (value >= 0) positive += value; else negative += value;
      }
    }
  } else {
    for (const { row, index: series } of visible) {
      const points = row.values.map((value, index) => ({ x: left + pitch * (index + 0.5), y: valuePosition(value) }));
      const path = chartLinePath(points, variant);
      const color = dataColor(palette, row.color);
      if (kind === 'AreaChart' && points.length) {
        shapes.push(<Path key={`area:${series}`} testID={`chart-area-${series}`}
          d={`${path} L${points[points.length - 1].x},${valuePosition(0)} L${points[0].x},${valuePosition(0)} Z`}
          fill={color} fillOpacity={0.16} />);
      }
      shapes.push(<Path key={`line:${series}`} testID={`chart-line-${series}`} d={path}
        fill="none" stroke={color} strokeWidth={2.5} strokeLinejoin="round" strokeLinecap="round"
        strokeDasharray={series % 3 === 1 ? '7 4' : series % 3 === 2 ? '2 3' : undefined} />);
      for (const [index, point] of points.entries()) {
        const id = `series:${series}:${index}`;
        shapes.push(<G key={id}>
          <Circle cx={point.x} cy={point.y} r={selected === id ? 5 : 3} fill={color}
            stroke={theme.surface} strokeWidth={selected === id ? 2 : 1} />
          <Circle testID={`chart-point-${series}-${index}`} cx={point.x} cy={point.y} r={16}
            fill="transparent" onPress={() => select(id)} />
        </G>);
      }
    }
  }
  return <>{labels}<Defs><ClipPath id={clipId}><Rect x={left - 2} y={top - 2} width={right - left + 4} height={bottom - top + 4} /></ClipPath></Defs>
    <G clipPath={`url(#${clipId})`}>{shapes}</G></>;
}

function PolarPlot({ kind, data, width, height, variant, semi, hidden, selected, select, palette, theme }: PlotProps) {
  const values = data.values.map((value, index) => hidden.has(index) ? 0 : value);
  const fractions = positiveFractions(values);
  const positive = values.some(value => value > 0);
  if (kind === 'SingleStackedBarChart') {
    const left = 12; const totalWidth = width - 24; const y = height / 2 - 18;
    let offset = left;
    return <><Rect x={left} y={y} width={totalWidth} height={36} rx={6} fill={theme.surfaceMuted} />
      {fractions.map((fraction, index) => {
        const x = offset; const segmentWidth = fraction * totalWidth; offset += segmentWidth;
        return segmentWidth > 0 ? <Rect key={index} testID={`chart-segment-${index}`} x={x} y={y}
          width={segmentWidth} height={36} fill={dataColor(palette, index)}
          opacity={selected && selected !== `slice:${index}` ? 0.4 : 1} onPress={() => select(`slice:${index}`)} /> : null;
      })}</>;
  }
  const center = { x: width / 2, y: semi ? height - 24 : height / 2 };
  const radius = Math.max(1, Math.min(width / 2 - 18, semi ? height - 44 : height / 2 - 18));
  if (kind === 'RadialChart') {
    const count = Math.max(1, values.length);
    const band = radius / count;
    const maximum = values.reduce((max, value) => Math.max(max, value), 0);
    return <>{values.map((value, index) => {
      const r = radius - band * (index + 0.5); const thickness = band * 0.68;
      if (hidden.has(index)) return null;
      return <G key={index}>
        <Circle cx={center.x} cy={center.y} r={r} fill="none" stroke={theme.surfaceMuted} strokeWidth={thickness} />
        {value > 0 && maximum > 0 ? <Path testID={`chart-radial-${index}`}
          d={chartArcPath(center, r, -90, -90 + 360 * (value / maximum))} fill="none"
          stroke={dataColor(palette, index)} strokeWidth={thickness} strokeLinecap="round"
          opacity={selected && selected !== `slice:${index}` ? 0.4 : 1}
          onPress={() => select(`slice:${index}`)} /> : null}
      </G>;
    })}</>;
  }
  let angle = semi ? -180 : -90;
  if (!positive) return <Path d={chartSectorPath(center, radius, variant === 'donut' ? radius * 0.6 : 0,
    semi ? -180 : -90, semi ? 0 : 270)} fill={theme.surfaceMuted} />;
  return <>{fractions.map((fraction, index) => {
    const start = angle; angle += (semi ? 180 : 360) * fraction;
    if (!fraction) return null;
    return <Path key={index} testID={`chart-slice-${index}`}
      d={chartSectorPath(center, radius, variant === 'donut' ? radius * 0.6 : 0, start, angle)}
      fill={dataColor(palette, index)} stroke={theme.surface} strokeWidth={1.5}
      opacity={selected && selected !== `slice:${index}` ? 0.4 : 1} onPress={() => select(`slice:${index}`)} />;
  })}</>;
}

function RadarPlot({ data, width, height, hidden, selected, select, palette, theme }: PlotProps) {
  const center = { x: width / 2, y: height / 2 };
  const radius = Math.max(1, Math.min(width / 2 - 48, height / 2 - 38));
  const visible = data.series.map((row, index) => ({ row, index })).filter(item => !hidden.has(item.index));
  let maximum = 1;
  for (const { row } of visible) for (const value of row.values) maximum = Math.max(maximum, value);
  const point = (index: number, fraction: number) => polarPoint(center, radius * fraction, -90 + 360 * index / Math.max(1, data.labels.length));
  const polygon = (points: ChartPoint[]) => chartLinePath(points, 'linear') + ' Z';
  return <>
    {[0.25, 0.5, 0.75, 1].map(step => <Path key={step}
      d={polygon(data.labels.map((_, index) => point(index, step)))} fill="none" stroke={theme.border} strokeWidth={0.7} />)}
    {data.labels.map((label, index) => {
      const edge = point(index, 1); const position = point(index, 1.16);
      return <G key={index}><Line x1={center.x} y1={center.y} x2={edge.x} y2={edge.y} stroke={theme.border} />
        <SvgText x={position.x} y={position.y + 4} textAnchor="middle" fontSize={11} fill={theme.muted}>{shortened(label, 8)}</SvgText>
      </G>;
    })}
    {visible.map(({ row, index: series }) => {
      const points = row.values.map((value, index) => point(index, Math.max(0, value) / maximum));
      const color = dataColor(palette, row.color);
      return <G key={series}>
        <Path testID={`chart-radar-${series}`} d={polygon(points)} fill={color} fillOpacity={0.15} stroke={color} strokeWidth={2} />
        {points.map((position, index) => <G key={index}>
          <Circle cx={position.x} cy={position.y} r={selected === `series:${series}:${index}` ? 5 : 3} fill={color} />
          <Circle testID={`chart-point-${series}-${index}`} cx={position.x} cy={position.y} r={15} fill="transparent"
            onPress={() => select(`series:${series}:${index}`)} />
        </G>)}
      </G>;
    })}
  </>;
}

function ScatterPlot({ data, width, height, hidden, selected, select, palette, theme }: PlotProps) {
  const points = data.scatter.filter(point => !hidden.has(point.series));
  const left = 56; const right = width - 18; const top = 18; const bottom = height - 36;
  let xLow = 0; let xHigh = 0; let yLow = 0; let yHigh = 0; let maxZ = 1;
  for (const point of points) {
    xLow = Math.min(xLow, point.x); xHigh = Math.max(xHigh, point.x);
    yLow = Math.min(yLow, point.y); yHigh = Math.max(yHigh, point.y); maxZ = Math.max(maxZ, point.z ?? 0);
  }
  const xDomain = { low: xLow, high: xHigh === xLow ? xLow + 1 : xHigh };
  const yDomain = { low: yLow, high: yHigh === yLow ? yLow + 1 : yHigh };
  return <>
    {ticks(yDomain).map(value => {
      const y = project(value, yDomain, bottom, top);
      return <G key={`y:${value}`}><Line x1={left} y1={y} x2={right} y2={y} stroke={theme.border} />
        <SvgText x={left - 7} y={y + 4} fill={theme.muted} fontSize={11} textAnchor="end">{chartTick(value)}</SvgText></G>;
    })}
    {ticks(xDomain).map(value => {
      const x = project(value, xDomain, left, right);
      return <G key={`x:${value}`}><Line x1={x} y1={top} x2={x} y2={bottom} stroke={theme.border} />
        <SvgText x={x} y={bottom + 19} fill={theme.muted} fontSize={11} textAnchor="middle">{chartTick(value)}</SvgText></G>;
    })}
    {points.map(point => {
      const x = project(point.x, xDomain, left, right); const y = project(point.y, yDomain, bottom, top);
      const radius = point.z === undefined ? 5 : 4 + 10 * Math.sqrt(Math.max(0, point.z) / maxZ);
      const color = dataColor(palette, point.series);
      return <G key={point.id}>
        <Circle cx={x} cy={y} r={radius} fill={color} fillOpacity={selected && selected !== point.id ? 0.35 : 0.8}
          stroke={selected === point.id ? theme.ink : theme.surface} strokeWidth={selected === point.id ? 2 : 1} />
        <Circle testID={`chart-${point.id}`} cx={x} cy={y} r={Math.max(18, radius)} fill="transparent" onPress={() => select(point.id)} />
      </G>;
    })}
  </>;
}

function NativeChart({ kind, props }: { kind: Kind; props: Record<string, unknown> }) {
  const theme = useOpenUITheme();
  const streaming = useIsStreaming();
  const { canInteract } = useDocumentInteraction();
  const disabled = streaming || !canInteract();
  const data = useMemo(() => readData(kind, props), [kind, props.labels, props.series, props.values, props.datasets]);
  const identity = JSON.stringify([kind, data]);
  const legendKey = JSON.stringify([kind, data.labels, data.names]);
  const guard = useFieldGuard(identity);
  const [width, setWidth] = useState(340);
  const [inspection, setInspection] = useState<{ key: string; id: string }>();
  const [visibility, setVisibility] = useState<{ key: string; hidden: ReadonlySet<number> }>({ key: legendKey, hidden: noHiddenSeries });
  const selected = inspection?.key === legendKey ? inspection.id : undefined;
  const hidden = visibility.key === legendKey ? visibility.hidden : noHiddenSeries;
  const [showData, setShowData] = useState(false);
  const [page, setPage] = useState(0);
  const id = useId().replace(/[^a-zA-Z0-9_-]/g, '');
  const palette = paletteFor(theme);
  const polar = kind === 'PieChart' || kind === 'RadialChart' || kind === 'SingleStackedBarChart';
  const variant = text(props.variant) || (kind === 'PieChart' ? 'pie' : 'linear');
  const semi = kind === 'PieChart' && props.appearance === 'semiCircular';
  const defaultHeight = kind === 'SingleStackedBarChart' ? 96 : semi ? 200
    : kind === 'HorizontalBarChart' ? Math.max(240, Math.min(640, data.labels.length * 42 + 60)) : 260;
  const height = number(props.height) && props.height > 0 ? Math.max(100, Math.min(1200, props.height)) : defaultHeight;
  const tooLarge = data.entries.length > MAX_PLOT_POINTS;
  const numericOverflow = !polar && kind !== 'RadarChart' && kind !== 'ScatterChart'
    && !chartDomain(data.series, data.labels.length, variant === 'stacked');
  const issue = data.issue ?? (numericOverflow ? '堆叠合计超出了有限数值范围。'
    : data.negative && (polar || kind === 'RadarChart') ? '此图表需要非负数。原始负数保留在完整数据中。' : undefined);
  const empty = !data.entries.length;
  const zero = polar && data.values.every((value, index) => hidden.has(index) || value <= 0);
  const selection = data.entries.find(entry => entry.id === selected);
  const totalPages = Math.max(1, Math.ceil(data.entries.length / PAGE_SIZE));
  const safePage = Math.min(page, totalPages - 1);
  const select = (entry: string) => { if (guard()) setInspection(previous => previous?.key === legendKey && previous.id === entry
    ? undefined : { key: legendKey, id: entry }); };
  const openData = () => { if (guard()) setShowData(true); };
  const plotProps: PlotProps = { kind, data, width, height, variant, semi, hidden, selected,
    select, palette, theme, clipId: `openui-plot-${id}` };
  const chartLabel = [titles[kind], text(props.xLabel), text(props.yLabel)].filter(Boolean).join(' · ');
  const notice = issue ? streaming ? '图表数据正在生成。' : issue
    : empty ? streaming ? '正在生成图表…' : '暂无数据'
      : tooLarge ? `共 ${data.entries.length} 个数据点。超过单图绘制上限，请分页查看完整数据。` : undefined;

  return <View testID={`openui-chart-${kind}`} style={{ gap: 10, minWidth: 0 }}
    onLayout={event => { const next = event.nativeEvent.layout.width; if (Number.isFinite(next) && next > 0) setWidth(Math.max(220, next)); }}>
    {text(props.yLabel) ? <Text style={{ color: theme.muted, fontSize: 12, lineHeight: 19 }}>{text(props.yLabel)}</Text> : null}
    <View style={{ borderRadius: 12, backgroundColor: theme.surface }}>
    <Pressable accessibilityRole="image" accessibilityLabel={chartLabel}
      accessibilityValue={{ text: selection?.text ?? (streaming ? '正在生成' : notice ?? '') }}
      accessibilityHint="轻点数据点查看数值；长按或使用辅助功能操作查看完整数据。"
      accessibilityActions={data.entries.length ? [{ name: 'showData', label: '查看完整数据' }] : []}
      onAccessibilityAction={event => { if (event.nativeEvent.actionName === 'showData') openData(); }}
      onLongPress={openData}>
      {notice ? <Text accessibilityRole={issue && !streaming ? 'alert' : undefined}
        style={{ color: issue ? theme.destructive : theme.muted, fontSize: 14, lineHeight: 22, padding: 18, paddingRight: 52 }}>{notice}</Text>
        : <Svg width="100%" height={height} viewBox={`0 0 ${width} ${height}`} accessible={false}>
          {polar ? <PolarPlot {...plotProps} /> : kind === 'RadarChart' ? <RadarPlot {...plotProps} />
            : kind === 'ScatterChart' ? <ScatterPlot {...plotProps} /> : <CartesianPlot {...plotProps} />}
        </Svg>}
      {zero && !notice ? <Text style={{ color: theme.muted, padding: 10, textAlign: 'center', fontSize: 14 }}>正值合计为 0</Text> : null}
      {streaming ? <View pointerEvents="none" style={{ position: 'absolute', left: 10, top: 6,
        padding: 5, borderRadius: 6, backgroundColor: theme.surface }}>
        <Text accessibilityLiveRegion="polite" style={{ color: theme.muted, fontSize: 12 }}>正在生成</Text>
      </View> : null}
    </Pressable>
      {data.entries.length > 0 ? <Pressable accessibilityRole="button" accessibilityLabel="查看完整数据"
        accessibilityState={{ disabled }} disabled={disabled} onPress={openData}
        style={{ position: 'absolute', right: 2, top: 0, minWidth: theme.controlMinHeight,
          minHeight: theme.controlMinHeight, alignItems: 'center', justifyContent: 'center' }}>
        <Text style={{ color: theme.muted, fontSize: 24 }}>⋯</Text>
      </Pressable> : null}
      {selection && !showData ? <View pointerEvents="none" style={{ position: 'absolute', left: 12, right: 12,
        bottom: 10, backgroundColor: theme.surfaceMuted, padding: 10, borderRadius: 8 }}>
        <Text accessibilityLiveRegion="polite" style={{ color: theme.ink, fontSize: 13, lineHeight: 20 }}>{selection.text}</Text>
      </View> : null}
    </View>
    {text(props.xLabel) ? <Text style={{ color: theme.muted, fontSize: 12, lineHeight: 19, textAlign: 'center' }}>{text(props.xLabel)}</Text> : null}
    {!tooLarge && data.names.length > 0 && <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 6 }}>
      {data.names.map((name, index) => {
        const color = dataColor(palette, data.series[index]?.color ?? index);
        const content = <View style={{ flexDirection: 'row', gap: 7, alignItems: 'center', minWidth: 0 }}>
          <View style={{ width: 9, height: 9, borderRadius: 5, backgroundColor: color }} />
          <Text style={{ color: theme.ink, fontSize: 13, lineHeight: 20, flexShrink: 1 }}>{name || `第 ${index + 1} 系列`}</Text>
        </View>;
        return kind === 'SingleStackedBarChart' ? <View key={index} style={{ padding: 8 }}>{content}</View>
          : <Pressable key={index} accessibilityRole="checkbox" accessibilityLabel={`显示 ${name || `第 ${index + 1} 系列`}`}
            accessibilityState={{ checked: !hidden.has(index), disabled }} disabled={disabled}
            onPress={() => { if (guard()) setVisibility(current => { const next = new Set(current.key === legendKey ? current.hidden : noHiddenSeries);
              if (next.has(index)) next.delete(index); else next.add(index); return { key: legendKey, hidden: next }; }); }}
            style={{ minHeight: theme.controlMinHeight, paddingHorizontal: 8, paddingVertical: 8, justifyContent: 'center',
              opacity: hidden.has(index) ? 0.45 : 1, minWidth: 0, maxWidth: '100%' }}>{content}</Pressable>;
      })}
    </View>}
    <Modal visible={showData} transparent animationType="fade" onRequestClose={() => setShowData(false)}>
      <View style={{ flex: 1, justifyContent: 'center', padding: 20, backgroundColor: '#00000066' }}>
        <View accessibilityViewIsModal style={{ maxHeight: '90%', width: '100%', maxWidth: 680,
          alignSelf: 'center', borderRadius: 16, backgroundColor: theme.surface, padding: 16, gap: 12 }}>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12, justifyContent: 'space-between' }}>
            <Text accessibilityRole="header" style={{ color: theme.ink, fontWeight: '600', fontSize: 17, lineHeight: 25, flexShrink: 1 }}>{titles[kind]} · 完整数据</Text>
            <ChartControl label="关闭数据" onPress={() => setShowData(false)} />
          </View>
          <Text style={{ color: theme.muted, fontSize: 13, lineHeight: 20 }}>共 {data.entries.length} 项 · 原始数值</Text>
          <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={{ gap: 0 }}>
      {data.entries.slice(safePage * PAGE_SIZE, (safePage + 1) * PAGE_SIZE).map(entry => <Pressable key={entry.id}
        accessibilityRole="button" accessibilityLabel={entry.text} accessibilityState={{ selected: selected === entry.id, disabled }}
        disabled={disabled} onPress={() => select(entry.id)}
        style={{ minHeight: theme.controlMinHeight, padding: 12, borderBottomWidth: 0.5, borderColor: theme.border,
          backgroundColor: selected === entry.id ? theme.surfaceMuted : theme.surface }}>
        <Text style={{ color: theme.ink, fontSize: 14, lineHeight: 22 }}>{entry.text}</Text>
      </Pressable>)}
          </ScrollView>
      {totalPages > 1 && <View style={{ flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: 8, paddingTop: 8 }}>
        <ChartControl label="上一页数据" disabled={disabled || safePage === 0}
          onPress={() => { if (guard()) setPage(Math.max(0, safePage - 1)); }} />
        <Text accessibilityLiveRegion="polite" style={{ color: theme.muted }}>{safePage + 1} / {totalPages}</Text>
        <ChartControl label="下一页数据" disabled={disabled || safePage >= totalPages - 1}
          onPress={() => { if (guard()) setPage(Math.min(totalPages - 1, safePage + 1)); }} />
      </View>}
        </View>
      </View>
    </Modal>
  </View>;
}

const chart = (kind: Kind): ComponentRenderer => ({ props }) => <NativeChart kind={kind} props={props} />;
const dataOnly: ComponentRenderer = () => null;
export const chartRenderers: Record<string, ComponentRenderer> = {
  BarChart: chart('BarChart'), LineChart: chart('LineChart'), AreaChart: chart('AreaChart'),
  RadarChart: chart('RadarChart'), HorizontalBarChart: chart('HorizontalBarChart'),
  PieChart: chart('PieChart'), RadialChart: chart('RadialChart'), SingleStackedBarChart: chart('SingleStackedBarChart'),
  ScatterChart: chart('ScatterChart'), Series: dataOnly, Slice: dataOnly, ScatterSeries: dataOnly, Point: dataOnly,
};
