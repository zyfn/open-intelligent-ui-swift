import type { ElementNode } from '@openuidev/react-lang';

export const text = (value: unknown, fallback = ''): string => typeof value === 'string' ? value : fallback;
export const record = (value: unknown): Record<string, unknown> =>
  value !== null && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {};
export const nodeProps = (value: unknown) => record(record(value).props);
export const elements = (value: unknown): ElementNode[] => Array.isArray(value)
  ? value.filter((item): item is ElementNode => record(item).type === 'element') : [];
export const finiteNumber = (value: unknown, fallback: number): number =>
  typeof value === 'number' && Number.isFinite(value) ? value : fallback;
