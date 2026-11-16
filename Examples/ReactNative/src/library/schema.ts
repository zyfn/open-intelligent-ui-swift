import { action, defineComponent, markReactive } from '@openuidev/lang-core';
import { z } from 'zod/v4';
import catalog from './catalog.generated.json';

type Parameter = {
  name: string;
  required: boolean;
  hasDefault: boolean;
  defaultValue: unknown;
  isBindable: boolean;
  schema: Record<string, unknown>;
};

export type CatalogComponent = {
  name: string;
  description: string;
  params: Parameter[];
};

export { catalog };

// Both the native registry and the headless contract export use this authoring
// path. A missing implementation fails before a prompt can advertise it.
export function defineCatalogComponents<Renderer>(renderers: Record<string, Renderer>) {
  return catalog.components.map(definition => {
    const component = renderers[definition.name];
    if (component === undefined) throw new Error(`Missing native renderer: ${definition.name}`);
    return defineComponent({ name: definition.name, description: definition.description,
      props: propsFromCatalog(definition), component });
  });
}

// This is a transport adapter for the selected catalog, not another schema.
// Preserve order: OpenUI Lang component arguments are positional.
export function propsFromCatalog(definition: CatalogComponent) {
  const shape: Record<string, z.ZodType> = {};
  for (const parameter of definition.params) {
    const ref = parameter.schema.$ref;
    if (ref && ref !== '#/$defs/ActionExpression') {
      throw new Error(`Unsupported catalog reference: ${definition.name}.${parameter.name}: ${ref}`);
    }
    let field: z.ZodType = ref
      ? action()
      : z.fromJSONSchema(parameter.schema, { registry: z.registry() });
    if (parameter.hasDefault && !Object.hasOwn(parameter.schema, 'default')) {
      field = field.default(parameter.defaultValue);
    }
    if (!parameter.required && !parameter.hasDefault) field = field.optional();
    if (parameter.isBindable) markReactive(field);
    shape[parameter.name] = field;
  }
  return z.object(shape);
}
