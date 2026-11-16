import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';

const source = new URL('../../../Sources/SwiftOpenUI/Resources/upstream-catalog.json', import.meta.url);
// This existing generated export includes the library's Map/MapPoint/SVG
// extensions and their slots. Never maintain another handwritten contract.
const nativeSource = new URL('../../../Tests/SwiftOpenUITests/Fixtures/AgentCasesContract/test-library-spec.json', import.meta.url);
const target = new URL('../src/library/catalog.generated.json', import.meta.url);
const input = await readFile(source);
const nativeInput = await readFile(nativeSource);
const catalog = JSON.parse(input.toString('utf8'));
const native = JSON.parse(nativeInput.toString('utf8'));
const components = Object.entries(native.components).map(([name, spec]) => {
  const schema = native.schema.$defs[name];
  if (!schema?.properties) throw new Error(`Missing exported component schema: ${name}`);
  const upstream = catalog.components.find(component => component.name === name);
  const params = Object.entries(schema.properties).map(([parameterName, parameterSchema]) => {
    const original = upstream?.params.find(parameter => parameter.name === parameterName);
    return {
      name: parameterName,
      required: schema.required?.includes(parameterName) ?? false,
      hasDefault: Object.hasOwn(parameterSchema, 'default'),
      defaultValue: parameterSchema.default ?? null,
      isBindable: original?.isBindable ?? false,
      schema: parameterSchema,
    };
  });
  // A stale export must not silently remove or reorder an upstream parameter.
  if (upstream && JSON.stringify(params.map(parameter => parameter.name))
    !== JSON.stringify(upstream.params.map(parameter => parameter.name))) {
    throw new Error(`Exported parameter order differs from the pinned catalog: ${name}`);
  }
  return { name, description: spec.description, signature: spec.signature, params,
    ...(schema.description ? { schemaDescription: schema.description } : {}) };
});
const output = JSON.stringify({
  generatedBy: 'scripts/catalog.mjs; do not edit parameter contracts here',
  revision: catalog.revision,
  catalogSHA256: createHash('sha256').update(input).digest('hex'),
  exportedContractSHA256: createHash('sha256').update(nativeInput).digest('hex'),
  root: catalog.root,
  components,
  componentGroups: native.componentGroups,
  promptOptions: catalog.promptOptions,
  sources: Object.fromEntries(Object.entries(catalog.sources).filter(([path]) => path.endsWith('/schema.ts'))),
}, null, 2) + '\n';

if (process.argv.includes('--check')) {
  if (await readFile(target, 'utf8') !== output) {
    throw new Error('RN catalog is stale. Run npm run catalog.');
  }
  console.log(`Catalog matches the canonical source (${components.length} components).`);
} else {
  await writeFile(target, output);
  console.log(`Generated ${components.length} component contracts.`);
}
