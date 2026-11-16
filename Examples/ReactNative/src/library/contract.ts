import { createLibrary, type PromptOptions } from '@openuidev/lang-core';
import { catalog, defineCatalogComponents } from './schema';
import { preserveCatalogSignatures } from './catalogPrompt';

// Host/model code can export a contract without loading React Native.
export function createContract() { return preserveCatalogSignatures(createLibrary({
  id: 'openui-rn-pilot',
  root: catalog.root,
  components: defineCatalogComponents(Object.fromEntries(catalog.components.map(component => [component.name, null]))),
  componentGroups: catalog.componentGroups,
})); }

export const promptOptions: PromptOptions = {
  bindings: true,
  toolCalls: false,
  examples: catalog.promptOptions.examples,
  additionalRules: [
    ...catalog.promptOptions.additionalRules.filter(rule => !/Multi-query refresh|re-evaluates all Queries/.test(rule)),
    'Use only the components in this library. Tool execution is owned by the host and is not configured in this renderer.',
    'TextContent supports native Markdown: paragraphs, headings, emphasis, links, lists, quotes, code and tables. Do not generate HTML.',
    'Form fields use their declared rules. A local validated action is not a completed remote business transaction.',
    'Images and external links are subject to host resource and action policies. Never invent a successful external action.',
    'Prefer column layout for reading. Use short row groups only when their content can wrap on a narrow phone.',
  ],
};
