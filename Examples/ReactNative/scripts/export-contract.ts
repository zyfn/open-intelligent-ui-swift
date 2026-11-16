import { createHash } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath, URL } from 'node:url';
import { createContract, promptOptions } from '../src/library/contract';
import { catalog } from '../src/library/schema';

async function main() {
  const contract = createContract();
  const prompt = contract.prompt(promptOptions);
  const output = process.argv[2] ? resolve(process.argv[2])
    : fileURLToPath(new URL('../../../outputs/react-native/contract/', import.meta.url));
  const spec = JSON.stringify({ ...contract.toSpec(), schema: contract.toJSONSchema() }, null, 2) + '\n';
  const manifest = {
    library: contract.id,
    root: contract.root,
    components: Object.keys(contract.components),
    upstreamRevision: catalog.revision,
    catalogSHA256: catalog.catalogSHA256,
    exportedContractSHA256: catalog.exportedContractSHA256,
    specSHA256: createHash('sha256').update(spec).digest('hex'),
    promptSHA256: createHash('sha256').update(prompt).digest('hex'),
  };
  await mkdir(output, { recursive: true });
  await Promise.all([
    writeFile(resolve(output, 'spec.json'), spec),
    writeFile(resolve(output, 'prompt.txt'), prompt),
    writeFile(resolve(output, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n'),
  ]);
  console.log(`Exported ${manifest.components.length} component contracts to ${output}`);
}

main().catch(error => { console.error(error); process.exitCode = 1; });
