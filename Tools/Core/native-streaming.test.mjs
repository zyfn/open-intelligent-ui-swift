// Exercise partition invariance at every prefix, including native readiness.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { createNativeRuntime } from './native-test-runtime.mjs';
const realm = createNativeRuntime({ setInterval, clearInterval });
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

// Record tolerant parsing and diagnostic delivery with the shipped OpenUI
// catalog. Inner quotes in the first input are intentionally not escaped.
const {spec: openUISpec} = JSON.parse(readFileSync(
 new URL('../../Sources/SwiftOpenUI/Resources/upstream-catalog.json', import.meta.url), 'utf8'));
const quotedTextCases = [
 {
  name: 'unescaped inner quotes retain prefixes and terminal diagnostics',
  source: String.raw`root = Stack([headline, verdictText])
headline = MarkDownRenderer("# 杭州好玩，但它不给"刺激"，给的是"松弛"")
verdictText = TextContent("杭州的好玩，是"待着舒服"，不是"玩得尽兴"。")`,
  texts: ['# 杭州好玩，但它不给', '杭州的好玩，是'],
  errors: [
   ['type-mismatch', 'headline', 'MarkDownRenderer', '/variant'],
   ['excess-args', 'headline', 'MarkDownRenderer', ''],
   ['type-mismatch', 'verdictText', 'TextContent', '/size'],
   ['excess-args', 'verdictText', 'TextContent', ''],
  ],
 },
 {
  name: 'escaped inner quotes preserve complete text through final delivery',
  source: String.raw`root = Stack([headline, verdictText])
headline = MarkDownRenderer("# 杭州好玩，但它不给\"刺激\"，给的是\"松弛\"")
verdictText = TextContent("杭州的好玩，是\"待着舒服\"，不是\"玩得尽兴\"。")`,
  texts: ['# 杭州好玩，但它不给"刺激"，给的是"松弛"', '杭州的好玩，是"待着舒服"，不是"玩得尽兴"。'],
  errors: [],
 },
];
for (const example of quotedTextCases) {
 test(example.name, () => {
  const batch = core.createParser(openUISpec.schema, openUISpec.root).parse(example.source);
  assert.equal(batch.root?.typeName, 'Stack');
  const children = batch.root.props.children;
  assert.deepEqual(plain(children.map(child => child.typeName)), ['MarkDownRenderer', 'TextContent']);
  assert.deepEqual([children[0].props.textMarkdown, children[1].props.text], example.texts);
  assert.equal(batch.meta.incomplete, false);
  assert.equal(bridge.nativeBudgetExceeded(batch), false);
  assert.deepEqual(plain(batch.meta.errors.map(error =>
   [error.code, error.statementId, error.component, error.path])), example.errors);

  const streamed = core.createStreamingParser(openUISpec.schema, openUISpec.root);
  for (const scalar of example.source) streamed.push(scalar);
  assert.deepEqual(snapshot(streamed.getResult(true)), snapshot(batch), 'terminal batch/scalar parity');
 });
}
