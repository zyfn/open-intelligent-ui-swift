import { createLibrary } from '@openuidev/react-lang';
import { catalog, defineCatalogComponents } from './schema';
import { renderers } from './components';
import { promptOptions } from './contract';

export { NativeThemeProvider, useOpenUITheme } from './theme';
export { NativeContentProvider } from './components/contentPolicy';

// Module lifetime: the same schema/library identity is reused across chunks.
export const library = createLibrary({
  id: 'openui-rn-pilot',
  root: catalog.root,
  components: defineCatalogComponents(renderers),
});

export const prompt = library.prompt(promptOptions);
