import { generatePrompt, type LibrarySpec, type PromptOptions } from '@openuidev/lang-core';
import catalog from './catalog.generated.json';

/**
 * The pinned catalog distinguishes a nullable/defaulted value from a positional
 * argument that may be omitted. The npm 1.1.1 authoring helper labels every
 * optional Zod field with `?`, including positions before later required args.
 * Keep the catalog's generated signatures and use the official prompt generator;
 * parsing, schemas, bindings, Store and Renderer remain the official instances.
 */
export function preserveCatalogSignatures<T extends {
  toSpec(): LibrarySpec;
  prompt(options?: PromptOptions): string;
}>(library: T): T {
  const originalSpec = library.toSpec.bind(library);
  const signatures = new Map(catalog.components.map(component => [component.name, component.signature]));
  library.toSpec = () => {
    const spec = originalSpec();
    return { ...spec, components: Object.fromEntries(Object.entries(spec.components).map(([name, component]) =>
      [name, { ...component, signature: signatures.get(name) ?? component.signature }])) };
  };
  library.prompt = options => generatePrompt({ ...library.toSpec(), ...options });
  return library;
}
