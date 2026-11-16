import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';

// Only the implemented names are selected here. All parameter contracts come
// from the same generated upstream catalog consumed by SwiftOpenUI.
const names = ['Stack', 'TextContent', 'CardHeader', 'Separator', 'Input', 'Button', 'Image'];
const source = new URL('../../../Sources/SwiftOpenUI/Resources/upstream-catalog.json', import.meta.url);
const target = new URL('../src/library/catalog.generated.json', import.meta.url);
const input = await readFile(source);
const catalog = JSON.parse(input.toString('utf8'));
const components = names.map(name => {
  const definition = catalog.components.find(component => component.name === name);
  if (!definition) throw new Error(`Missing upstream component: ${name}`);
  return definition;
});
const output = JSON.stringify({
  generatedBy: 'scripts/catalog.mjs; do not edit parameter contracts here',
  revision: catalog.revision,
  catalogSHA256: createHash('sha256').update(input).digest('hex'),
  root: catalog.root,
  components,
  sources: Object.fromEntries(Object.entries(catalog.sources).filter(([path]) =>
    names.some(name => path.endsWith(`/genui-lib/${name}/schema.ts`)))),
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
