export type ChartPoint = Readonly<{ x: number; y: number }>;
export type ChartDomain = Readonly<{ low: number; high: number }>;
export type ChartSeries = Readonly<{ name: string; values: readonly number[] }>;

const coordinate = (value: number) => Number(value.toFixed(3));
const pair = (point: ChartPoint) => `${coordinate(point.x)},${coordinate(point.y)}`;

/** Keep mixed-sign and very large finite numbers in the same finite coordinate space. */
export function project(value: number, domain: ChartDomain, from: number, to: number): number {
  const magnitude = Math.max(Math.abs(domain.low), Math.abs(domain.high), 1);
  const low = domain.low / magnitude;
  const span = domain.high / magnitude - low;
  return from + (span > 0 ? (value / magnitude - low) / span : 0.5) * (to - from);
}

export function chartDomain(series: readonly ChartSeries[], count: number, stacked: boolean): ChartDomain | undefined {
  let low = 0;
  let high = 0;
  for (let index = 0; index < count; index++) {
    let positive = 0;
    let negative = 0;
    for (const row of series) {
      const value = row.values[index];
      if (!Number.isFinite(value)) return;
      if (stacked) {
        if (value >= 0) positive += value;
        else negative += value;
      } else {
        low = Math.min(low, value);
        high = Math.max(high, value);
      }
    }
    if (stacked) {
      if (!Number.isFinite(positive) || !Number.isFinite(negative)) return;
      low = Math.min(low, negative);
      high = Math.max(high, positive);
    }
  }
  return { low, high: high === low ? low + 1 : high };
}

/** Natural cubic interpolation: solve the tridiagonal control-point system. */
function naturalControls(values: readonly number[]): { first: number[]; second: number[] } {
  const count = values.length - 1;
  const diagonal = new Array<number>(count);
  const right = new Array<number>(count);
  const first = new Array<number>(count);
  const second = new Array<number>(count);
  diagonal[0] = 2;
  right[0] = values[0] + 2 * values[1];
  for (let index = 1; index < count; index++) {
    const lower = index === count - 1 ? 2 : 1;
    const multiplier = lower / diagonal[index - 1];
    diagonal[index] = (index === count - 1 ? 7 : 4) - multiplier;
    right[index] = (index === count - 1 ? 8 * values[index] + values[index + 1]
      : 4 * values[index] + 2 * values[index + 1]) - multiplier * right[index - 1];
  }
  first[count - 1] = right[count - 1] / diagonal[count - 1];
  for (let index = count - 2; index >= 0; index--) {
    first[index] = (right[index] - first[index + 1]) / diagonal[index];
  }
  for (let index = 0; index < count - 1; index++) second[index] = 2 * values[index + 1] - first[index + 1];
  second[count - 1] = (values[count] + first[count - 1]) / 2;
  return { first, second };
}

export function chartLinePath(points: readonly ChartPoint[], variant: string): string {
  if (!points.length) return '';
  let path = `M${pair(points[0])}`;
  if (variant === 'natural' && points.length > 2) {
    const x = naturalControls(points.map(point => point.x));
    const y = naturalControls(points.map(point => point.y));
    for (let index = 0; index < points.length - 1; index++) {
      path += ` C${pair({ x: x.first[index], y: y.first[index] })} ${pair({ x: x.second[index], y: y.second[index] })} ${pair(points[index + 1])}`;
    }
    return path;
  }
  for (let index = 1; index < points.length; index++) {
    const previous = points[index - 1];
    const point = points[index];
    if (variant === 'step') {
      const middle = (previous.x + point.x) / 2;
      path += ` H${coordinate(middle)} V${coordinate(point.y)} H${coordinate(point.x)}`;
    } else path += ` L${pair(point)}`;
  }
  return path;
}

export function polarPoint(center: ChartPoint, radius: number, degrees: number): ChartPoint {
  const angle = degrees * Math.PI / 180;
  return { x: center.x + Math.cos(angle) * radius, y: center.y + Math.sin(angle) * radius };
}

function arcSegments(center: ChartPoint, radius: number, start: number, end: number): string {
  const sweep = end - start;
  if (!sweep || radius <= 0) return '';
  const count = Math.max(1, Math.ceil(Math.abs(sweep) / 180));
  let path = '';
  for (let index = 1; index <= count; index++) {
    const point = polarPoint(center, radius, start + sweep * index / count);
    path += ` A${coordinate(radius)},${coordinate(radius)} 0 0 ${sweep >= 0 ? 1 : 0} ${pair(point)}`;
  }
  return path;
}

/** Splitting a full circle into two arcs avoids SVG's coincident-endpoint empty path. */
export function chartArcPath(center: ChartPoint, radius: number, start: number, end: number): string {
  return `M${pair(polarPoint(center, radius, start))}${arcSegments(center, radius, start, end)}`;
}

export function chartSectorPath(center: ChartPoint, outer: number, inner: number, start: number, end: number): string {
  if (!(end > start) || outer <= 0) return '';
  const outerStart = polarPoint(center, outer, start);
  const edge = arcSegments(center, outer, start, end);
  if (inner <= 0) return `M${pair(center)} L${pair(outerStart)}${edge} Z`;
  const innerEnd = polarPoint(center, inner, end);
  return `M${pair(outerStart)}${edge} L${pair(innerEnd)}${arcSegments(center, inner, end, start)} Z`;
}

/** Positive proportions without overflowing when several finite values are near MAX_VALUE. */
export function positiveFractions(values: readonly number[]): number[] {
  let magnitude = 0;
  for (const value of values) magnitude = Math.max(magnitude, value);
  if (!magnitude) return values.map(() => 0);
  const normalized = values.map(value => Math.max(0, value) / magnitude);
  const total = normalized.reduce((sum, value) => sum + value, 0);
  return normalized.map(value => value / total);
}

export function chartTick(value: number): string {
  if (!value) return '0';
  const size = Math.abs(value);
  return size >= 1_000_000 || size < 0.001 ? value.toExponential(2)
    : String(Number(value.toPrecision(4)));
}
