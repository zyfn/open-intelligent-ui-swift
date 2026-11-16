import examples from '../../../Gallery/Resources/Components/openui.json';
import type { GallerySample } from './samples';

export type ComponentSample = GallerySample & Readonly<{ category: string }>;

// These are the existing OpenUI Gallery programs, not rewritten RN fixtures.
export const componentSamples: readonly ComponentSample[] = Object.entries(examples).map(([name, sample]) => ({
  id: `component-${name}`, label: name, title: name, category: sample.category, source: sample.program,
}));
