const fs = require('fs');
const path = require('path');
const esbuild = require('esbuild');

const output = process.argv[2];
if (!output) throw new Error('Pass a generated output path.');
esbuild.build({
  entryPoints: [path.join(__dirname, 'entry.ts')], bundle: true, write: false,
  minify: true, legalComments: 'inline', format: 'iife', platform: 'browser', target: 'es2020',
  nodePaths: (process.env.NODE_PATH || '').split(path.delimiter).filter(Boolean),
  plugins: [{ name: 'function-descriptors', setup(build) {
    build.onResolve({filter: /^@openuidev\/react-lang$/}, () => ({path: path.join(__dirname, 'authoring.ts')}));
  }}]
}).then(result => {
  fs.mkdirSync(path.dirname(output), {recursive: true});
  fs.writeFileSync(output, '/* Fixed upstream functions: thesysdev/open-intelligent-ui 16ef26475999e3a021a50b1607a03717c0721255 (MIT), Zod (MIT). No parser/evaluator or generated code execution. See THIRD-PARTY-NOTICES.txt. */\n' + result.outputFiles[0].text);
}).catch(error => { console.error(error); process.exitCode = 1; });
