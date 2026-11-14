// Keep the existing native JSON Schema wire spelling when patched Zod folds
// bare anyOf branches into a type array. This changes representation only:
// no validation, signature printer, component order, or source parser lives here.
const maps = new Set(['properties', '$defs', 'definitions', 'patternProperties', 'dependentSchemas']);
const children = new Set(['items', 'additionalProperties', 'additionalItems', 'not', 'contains',
  'if', 'then', 'else', 'propertyNames', 'unevaluatedProperties', 'unevaluatedItems']);
const arrays = new Set(['anyOf', 'oneOf', 'allOf', 'prefixItems']);
export function preserveSchemaEmission(schema) {
  if (!schema || typeof schema !== 'object' || Array.isArray(schema)) return schema;
  return Object.fromEntries(Object.entries(schema).map(([key, value]) => {
    if (key === 'type' && Array.isArray(value) && !Object.hasOwn(schema, 'anyOf'))
      return ['anyOf', value.map(type => ({ type }))];
    if (maps.has(key) && value && typeof value === 'object' && !Array.isArray(value))
      return [key, Object.fromEntries(Object.entries(value).map(([name, child]) => [name, preserveSchemaEmission(child)]))];
    if (children.has(key)) return [key, Array.isArray(value) ? value.map(preserveSchemaEmission) : preserveSchemaEmission(value)];
    if (arrays.has(key) && Array.isArray(value)) return [key, value.map(preserveSchemaEmission)];
    if ((key === 'functions' || key === 'actions') && value && typeof value === 'object')
      return [key, Object.fromEntries(Object.entries(value).map(([name, call]) => [name,
        Object.fromEntries(Object.entries(call).map(([field, data]) =>
          [field, field === 'params' || field === 'returns' ? preserveSchemaEmission(data) : data]))]))];
    // Defaults, enums, const, examples and extension metadata are source data,
    // including business objects containing a field named "type".
    return [key, value];
  }));
}
