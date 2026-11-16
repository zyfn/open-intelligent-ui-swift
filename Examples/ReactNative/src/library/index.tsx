import { createLibrary } from '@openuidev/react-lang';
import { catalog, defineCatalogComponents } from './schema';
import { renderers } from './components';
import { promptOptions } from './contract';
import { preserveCatalogSignatures } from './catalogPrompt';

export { NativeThemeProvider, useOpenUITheme } from './theme';
export { NativeContentProvider } from './components/contentPolicy';
export { NativeMapProvider } from './components/MapComponent';

// Module lifetime: the same schema/library identity is reused across chunks.
export const library = preserveCatalogSignatures(createLibrary({
  id: 'openui-rn-pilot',
  root: catalog.root,
  components: defineCatalogComponents(renderers),
  componentGroups: catalog.componentGroups,
}));

export const prompt = library.prompt(promptOptions);
