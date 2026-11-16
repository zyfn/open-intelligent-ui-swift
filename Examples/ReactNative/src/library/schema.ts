import { action, defineComponent, markReactive, tagSchemaId } from '@openuidev/lang-core';
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
  schemaDescription?: string;
};

export { catalog };

// Both the native registry and the headless contract export use this authoring
// path. A missing implementation fails before a prompt can advertise it.
export function defineCatalogComponents<Renderer>(renderers: Record<string, Renderer>) {
  const schemas = new Map<string, z.ZodObject>();
  const reference = (name: string): z.ZodType => {
    if (!catalog.components.some(definition => definition.name === name)) {
      throw new Error(`Unsupported catalog reference: ${name}`);
    }
    const lazy = z.lazy(() => {
      const schema = schemas.get(name);
      if (!schema) throw new Error(`Unresolved catalog reference: ${name}`);
      return schema;
    });
    tagSchemaId(lazy, name);
    return lazy;
  };
  for (const definition of catalog.components) {
    let schema = propsFromCatalog(definition, reference);
    if ('schemaDescription' in definition && typeof definition.schemaDescription === 'string') {
      schema = schema.describe(definition.schemaDescription);
    }
    schemas.set(definition.name, schema);
  }
  return catalog.components.map(definition => {
    const component = renderers[definition.name];
    if (component === undefined) throw new Error(`Missing native renderer: ${definition.name}`);
    return defineComponent({ name: definition.name, description: definition.description,
      props: schemas.get(definition.name)!, component });
  });
}

function containsReference(schema: unknown): boolean {
  return !!schema && typeof schema === 'object' && (Object.hasOwn(schema, '$ref')
    || Object.values(schema).some(containsReference));
}

/** Delegate plain JSON Schema to Zod; only component references need adaptation. */
function fromSchema(schema: Record<string, unknown>, reference?: (name: string) => z.ZodType): z.ZodType {
  if (schema.type === 'object' && schema.propertyNames && typeof schema.propertyNames === 'object'
    && schema.additionalProperties && typeof schema.additionalProperties === 'object') {
    return z.record(z.string(), fromSchema(schema.additionalProperties as Record<string, unknown>, reference));
  }
  if (!containsReference(schema)) return z.fromJSONSchema(schema, { registry: z.registry() });
  let field: z.ZodType;
  if (typeof schema.$ref === 'string') {
    if (schema.$ref === '#/$defs/ActionExpression') field = action();
    else if (schema.$ref.startsWith('#/$defs/') && reference) field = reference(schema.$ref.slice(8));
    else throw new Error(`Unsupported catalog reference: ${schema.$ref}`);
  } else if (Array.isArray(schema.anyOf)) {
    const choices = schema.anyOf.map(item => fromSchema(item, reference));
    field = choices.length === 1 ? z.union([choices[0]]) : z.union(choices as [z.ZodType, z.ZodType, ...z.ZodType[]]);
  } else if (schema.type === 'array' && schema.items && typeof schema.items === 'object') {
    let array = z.array(fromSchema(schema.items as Record<string, unknown>, reference));
    if (typeof schema.minItems === 'number') array = array.min(schema.minItems);
    if (typeof schema.maxItems === 'number') array = array.max(schema.maxItems);
    field = array;
  } else if (schema.type === 'object') {
    const required = new Set(Array.isArray(schema.required) ? schema.required : []);
    const shape = Object.fromEntries(Object.entries((schema.properties ?? {}) as Record<string, Record<string, unknown>>)
      .map(([name, child]) => {
        const value = fromSchema(child, reference);
        return [name, required.has(name) ? value : value.optional()];
      }));
    field = z.object(shape);
  } else throw new Error('Unsupported reference-bearing catalog schema');
  if (Object.hasOwn(schema, 'default')) field = field.default(schema.default);
  return field;
}

// This is a transport adapter for the selected catalog, not another schema.
// Preserve order: OpenUI Lang component arguments are positional.
export function propsFromCatalog(definition: CatalogComponent, reference?: (name: string) => z.ZodType) {
  const shape: Record<string, z.ZodType> = {};
  for (const parameter of definition.params) {
    let field: z.ZodType = fromSchema(parameter.schema, reference);
    if (parameter.hasDefault && !Object.hasOwn(parameter.schema, 'default')) {
      field = field.default(parameter.defaultValue);
    }
    if (!parameter.required) field = field.optional();
    if (parameter.isBindable) markReactive(field);
    shape[parameter.name] = field;
  }
  return z.object(shape);
}
