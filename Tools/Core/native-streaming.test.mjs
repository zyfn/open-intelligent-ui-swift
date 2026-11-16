// Exercise partition invariance at every prefix, including native readiness.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';
const realm=vm.createContext({__utf8Encode:v=>[...Buffer.from(v)],__utf8Decode:v=>Buffer.from(v).toString('utf8'),setInterval,clearInterval});
vm.runInContext(readFileSync(process.env.OPENUI_NATIVE_CORE_JS ?? new URL('../../Sources/SwiftLang/Resources/lang-core.js', import.meta.url),'utf8'),realm,{timeout:5000});
const bridge = realm.SwiftCore, core = bridge.api;
const defs={Box:{value:{}},Stack:{children:{}},Image:{alt:{type:'string'},src:{type:'string'}},Button:{label:{type:'string'},action:{}},Input:{value:{},hint:{type:'string'}}};
const schema={$defs:Object.fromEntries(Object.entries(defs).map(([k,properties])=>[k,{type:'object',properties,required:[Object.keys(properties)[0]]}])),properties:Object.fromEntries(Object.keys(defs).map(k=>[k,{$ref:'#/$defs/'+k}]))};
const plain=v=>JSON.parse(JSON.stringify(v));
function snapshot(result){
 const trace=[];const seen=new Set();
 const visit=(v,path)=>{
  if(!v||typeof v!=='object'||seen.has(v))return;seen.add(v);
  trace.push([path,bridge.sourceComplete(v),plain(bridge.sourcePresentation(v))]);
  if(Array.isArray(v))v.forEach((x,i)=>visit(x,path+'/'+i));
  else Object.entries(v).forEach(([k,x])=>visit(x,path+'/'+k));
 };
 visit(result.root,'root');visit(result.rootExpression,'expr');
 return plain({root:result.root,rootExpression:result.rootExpression,state:result.stateDeclarations,queries:result.queryStatements,mutations:result.mutationStatements,meta:result.meta,limit:bridge.nativeBudgetExceeded(result),trace});
}
const cases=[
 'root=Box("ready")\nother=Box("tail")',
 'root=alias\nalias=Box("ready")\nother=Box("tail")',
 'root=Stack([a,b])\na=shared\nb=shared\nshared=Button("Go",@OpenUrl("https://a.test/path"))',
 '$value="first"\nroot=Input($value,"hint")\n$value="second"',
 'root=Box(1)\nroot=Box([2,3,4])',
 'root=Box(a)\na=3\na=12',
 'root=Box(true ? [1,2] : [3,4])',
 'x=true\nroot=x\n? Box("yes")\n: Box("no")',
 'x=true\nroot=x\n// comment\n? Box("yes")\n: Box("no")',
 'x=true\nroot=x\n# comment\n? Box("yes")\n: Box("no")',
 'root=Stack([Button("ok",@ToAssistant("yes")),Button("pending",@ToAssistant("tail"))])',
 'root=Stack([Image("alt","https://example.test/a"),Image("alt",url)])\nurl="https://example.test/😀"',
 'root=Box("\\uD83D\\uDE00\\u0000\\uD800\\n\\\\\\\"")',
 'root=Box([1e-20,2e+1,-0,1.2e10])',
 'root=Box({x:1,y:[1,2],nested:{a:"value",b:true}})',
 'root=Box(q.items)\nq=Query("load",{id:$id},{items:[]})\n$id=1',
 '$items=[1,2,3]\nroot=Stack(@Each($items,i,Button(@String(i),@ToAssistant(i))))',
 'root=Stack(@Each(q,i,Button(i.label,@ToAssistant(i.id))))\nq=Query("load",{},[])',
 'root=Box(@Each([1,2],i,@Each([3,4],j,[i,j])))',
 'root=Box(@Each([1,2],i,@Each([3,4],i,i)))',
 'root=Box(@Each([1,2],"x",{nested:x}))',
 'root=Box(missing)\nmissing=alias\nalias=Box("done")',
 '```openui\nroot=Box("ready")\n```',
 'Header\n```openui\nroot=Box("ready")\n```\nFooter',
 'root=Box("http://example.test/#hash") # comment\nq=1',
 'root=Box("A");\nother=1',
];
// This is a partition-invariance check, not an independent official oracle.
// Compare every intermediate prefix, including private readiness. The official
// compatibility runner separately checks the protocol against pinned upstream.
for (const [index, source] of cases.entries()) {
 test(`intermediate streaming partition invariant ${index + 1}`, () => {
  for (const width of [1, 2, 7]) {
   const parser = core.createStreamingParser(schema);
   let prefix = '';
   for (let offset = 0; offset < source.length; offset += width) {
    const chunk = source.slice(offset, offset + width);
    prefix += chunk;
    const incremental = snapshot(parser.push(chunk));
    const fresh = snapshot(core.createStreamingParser(schema).set(prefix));
    assert.deepEqual(incremental, fresh,
     `chunk width ${width}, prefix ${JSON.stringify(prefix)}`);
   }
   assert.deepEqual(snapshot(parser.getResult(true)),
    snapshot(core.createStreamingParser(schema).set(source, true)), 'terminal snapshot');
  }
 });
}
