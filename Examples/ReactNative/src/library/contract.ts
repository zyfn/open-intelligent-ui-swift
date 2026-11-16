import { createLibrary, type PromptOptions } from '@openuidev/lang-core';
import { catalog, defineCatalogComponents } from './schema';

// Host/model code can export a contract without loading React Native.
export function createContract() { return createLibrary({
  id: 'openui-rn-pilot',
  root: catalog.root,
  components: defineCatalogComponents(Object.fromEntries(catalog.components.map(component => [component.name, null]))),
}); }

export const promptOptions: PromptOptions = {
  bindings: true,
  toolCalls: false,
  additionalRules: [
    'Use only the components in this library. Form and FormControl are not available.',
    'TextContent supports native Markdown: paragraphs, headings, emphasis, links, lists, quotes, code and tables. Do not generate HTML.',
    'Input rules provide field-level feedback. Do not describe a local action as a validated form submission or a completed business transaction.',
    'Images and external links are subject to host resource and action policies. Never invent a successful external action.',
    'Prefer column layout for reading. Use short row groups only when their content can wrap on a narrow phone.',
  ],
};
