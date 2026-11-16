import { prepareCoreSource, upstreamFile, upstreamFiles } from "../upstream.mjs";
import { groupNotes, promptOptions } from './prompt-options.mjs';
// Export the pinned upstream library's schemas. Rendering functions are erased
// only in this build-time projection. The shared Zod export adapter preserves
// historical union schemas without changing Zod runtime validation.
import { build } from '../Core/node_modules/esbuild/lib/main.js';
import { zodJSONSchemaCompatibilityPlugin } from '../Core/compat.mjs';
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
const here = dirname(fileURLToPath(import.meta.url));
const root = prepareCoreSource();
const pin = '9823ec05d4b29bc78d101676dc16b44fe17f1830';
const git = path => upstreamFile(pin,path);
const prefix = 'packages/react-ui/src/genui-lib/';
const inputs = new Map();
const files=new Set(upstreamFiles(pin,'packages/react-ui/src'));
function eraseRender(source) {
  // Scan balanced JS tokens, treating strings/comments as opaque. Only the
  // `component` property of defineComponent is replaced, never its props.
  const tokens = /\/\*[\s\S]*?\*\/|\/\/[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`|[{}()[\],]|\bcomponent\s*:/g;
  let match, edits=[];
  while ((match=tokens.exec(source))) {
    if (!/^component\s*:/.test(match[0])) continue;
    const start=tokens.lastIndex; let depth=0, next;
    while ((next=tokens.exec(source))) {
      const t=next[0];
      if (depth===0 && (t===',' || t==='}')) { edits.push([start,next.index]); tokens.lastIndex=next.index; break; }
      if (['{','(','['].includes(t)) depth++;
      if (['}',')',']'].includes(t)) depth--;
    }
  }
  for (const [a,b] of edits.reverse()) source=source.slice(0,a)+' () => null'+source.slice(b);
  return source;
}
const tmp=join(root,'work/component-catalog'); mkdirSync(tmp,{recursive:true});
const entry=`import {openuiLibrary} from 'catalog:library';
import {FollowUpBlock} from 'catalog:followup-block';
import {FollowUpItem} from 'catalog:followup-item';
import {compileSchema,createParser} from '${join(root,'packages/lang-core/src/parser/parser.ts')}';
import {isReactiveSchema} from '${join(root,'packages/lang-core/src/reactive.ts')}';
const library=openuiLibrary.extend({components:{add:[FollowUpBlock,FollowUpItem]}});
const notes=${JSON.stringify(groupNotes)};
const componentGroups=library.componentGroups.map(group=>({...group,notes:notes[group.name]??group.notes}));
const spec={...library.toSpec(),componentGroups}, compiled=compileSchema(spec.schema);
const promptOptions=${JSON.stringify(promptOptions)};
export function parseReference(source){return createParser(spec.schema).parse(source).meta.errors;}
export const catalog={revision:${JSON.stringify(pin)},root:library.root,componentGroups,components:Object.entries(library.components).map(([name,c])=>({name,description:c.description,params:compiled.get(name).params.map(p=>({name:p.name,required:p.required,hasDefault:Object.hasOwn(p.schema??{},'default'),defaultValue:p.defaultValue??null,isBindable:isReactiveSchema(c.props.shape[p.name]),schema:spec.schema.$defs[name].properties[p.name]}))})),spec,promptOptions};`;
const result=await build({stdin:{contents:entry,resolveDir:root,loader:'ts'},bundle:true,write:false,platform:'node',format:'esm',target:'node20',nodePaths:[join(here,'../Core/node_modules')],plugins:[zodJSONSchemaCompatibilityPlugin(),{name:'reference-catalog',setup(b){
  b.onResolve({filter:/^catalog:library$/},()=>({path:prefix+'openuiLibrary.tsx',namespace:'upstream'}));
  b.onResolve({filter:/^catalog:followup-block$/},()=>({path:prefix+'FollowUpBlock/index.tsx',namespace:'upstream'}));
  b.onResolve({filter:/^catalog:followup-item$/},()=>({path:prefix+'FollowUpItem/index.tsx',namespace:'upstream'}));
  b.onResolve({filter:/^@openuidev\/react-lang$/},()=>({path:'core',namespace:'bridge'}));
  b.onLoad({filter:/.*/,namespace:'bridge'},()=>({contents:`export const FormNameContext=null,FormValidationContext=null;export const useFormName=()=>{throw Error('Unexpected renderer execution')},useFormValidation=useFormName,useGetFieldValue=useFormName,useSetFieldValue=useFormName,useIsStreaming=useFormName,useCreateFormValidation=useFormName,useTriggerAction=useFormName;export * from '${join(root,'packages/lang-core/src/index.ts')}';import {markReactive} from '${join(root,'packages/lang-core/src/reactive.ts')}';export function reactive(schema){markReactive(schema);return schema;}`,loader:'ts',resolveDir:root}));
  b.onResolve({filter:/.*/,namespace:'upstream'},args=>{
    if(args.path.startsWith('zod'))return;
    if(!args.path.startsWith('.'))return {path:args.path,external:true,sideEffects:false};
    const path=resolve('/',dirname(args.importer),args.path).slice(1);
    if(!path.startsWith(prefix) && !path.endsWith('components/_shared/icons'))return {path:args.path,external:true,sideEffects:false};
    for(const name of [path,path+'.ts',path+'.tsx',path+'/index.ts',path+'/index.tsx'])if(files.has(name))return {path:name,namespace:'upstream'};
    throw Error('Unresolved reference '+path);
  });
  b.onLoad({filter:/.*/,namespace:'upstream'},args=>{
    const path=args.path.endsWith('components/_shared/icons/index.ts')?args.path.replace('index.ts','schema.ts'):args.path;
    const source=git(path);inputs.set(path,createHash('sha256').update(source).digest('hex'));
    return {contents:eraseRender(source)+(path.endsWith('icons/schema.ts')?'\nexport const IconWrapper=()=>null;':''),loader:'tsx',resolveDir:join(here,'../Core')};
  });
}}]});
const modulePath=join(tmp,'reference.mjs');writeFileSync(modulePath,result.outputFiles[0].text);
const {catalog,parseReference}=await import(modulePath+'?'+Date.now());
// 82 pinned general-library components plus FollowUpBlock/FollowUpItem, which
// upstream registers only in the chat preset; the native SDK adopts them too.
if(catalog.components.length!==84)throw Error('Expected 84 default components');
// Presentation guidance is local to OpenUI; schemas stay pinned upstream.
if(Object.keys(catalog.promptOptions).sort().join(',')!=='additionalRules,examples')
  throw Error('Review OpenUI prompt preset fields');
for(const key of ['additionalRules','examples'])
  if(!Array.isArray(catalog.promptOptions[key]) || !catalog.promptOptions[key].every(value=>typeof value==='string'))
    throw Error('Invalid OpenUI prompt preset '+key);
for(const [index,example] of catalog.promptOptions.examples.entries()){
  const errors=parseReference(example);
  if(errors.length)throw Error(`OpenUI prompt example ${index+1} is invalid: ${JSON.stringify(errors)}`);
}
catalog.sources=Object.fromEntries([...inputs].sort());
catalog.promptSource={path:'Tools/Presentation/prompt-options.mjs',
  sha256:createHash('sha256').update(readFileSync(join(here,'prompt-options.mjs'))).digest('hex')};
const destination=resolve(here,'../../Sources/SwiftOpenUI/Resources/upstream-catalog.json');
const text=JSON.stringify(catalog,null,2)+'\n';
if(process.argv.includes('--check')){if(!existsSync(destination)||readFileSync(destination,'utf8')!==text)throw Error('Catalog differs from reference');}
else writeFileSync(destination,text);
console.log(`Upstream catalog: ${catalog.components.length} components; ${inputs.size} pinned source files`);
