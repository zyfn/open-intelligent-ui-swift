// These contracts distinguish syntax metadata reuse from Lang value caching.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const script = readFileSync(process.env.OPENUI_NATIVE_CORE_JS ??
  new URL('../../Sources/SwiftLang/Resources/lang-core.js', import.meta.url), 'utf8');
const schema = {
  $defs: {
    Box: {type:'object',properties:{value:{}},required:['value']},
    Stack: {type:'object',properties:{children:{}},required:['children']},
  },
  properties:{Box:{$ref:'#/$defs/Box'},Stack:{$ref:'#/$defs/Stack'}},
  functions:{Probe:{params:{type:'object',properties:{}}}},
};
function runtime() {
  const realm = vm.createContext({__utf8Encode:value=>[...Buffer.from(value)],
    __utf8Decode:value=>Buffer.from(value).toString('utf8')});
  vm.runInContext(script, realm);
  const bridge = realm.SwiftCore;
  return {bridge, parser:bridge.api.createStreamingParser(schema), library:bridge.library(schema,{})};
}
function accepted(bridge, result) {
  assert.equal(bridge.nativeBudgetExceeded(result), false);
  return result.root;
}

test('completed syntax still creates fresh values per pass and preserves aliases within a pass', () => {
  const {bridge,parser} = runtime();
  let result = parser.push('root=Stack([a,a,b,tail])\na=Box({x:[1,2]})\nb=a\ntail=Box("');
  let previous = accepted(bridge,result);
  for (let index = 0; index < 20; index++) {
    result = parser.push('x');
    const root = accepted(bridge,result), children = root.props.children;
    assert.equal(children[0],children[1], 'one pass memoizes a repeated declaration');
    assert.notEqual(children[0],children[2], 'an alias with another statement ID keeps the official shallow copy');
    assert.equal(children[0].props,children[2].props);
    assert.notEqual(root,previous);
    assert.notEqual(children[0],previous.props.children[0]);
    assert.notEqual(children[0].props.value,previous.props.children[0].props.value);
    previous = root;
  }
});

test('a changing trailing statement still changes global partial without rewriting old snapshots', () => {
  const {bridge,parser} = runtime();
  const before = accepted(bridge,parser.push('root=Stack([fixed,tail])\nfixed=Box("stable")\ntail=Box("'));
  const readiness = JSON.stringify(bridge.sourcePresentation(before.props.children[0]));
  assert.equal(before.props.children[0].partial,true);
  const after = accepted(bridge,parser.push('done")',true));
  assert.equal(after.props.children[0].partial,false);
  assert.equal(before.props.children[0].partial,true);
  assert.equal(JSON.stringify(bridge.sourcePresentation(before.props.children[0])),readiness);
});

test('completed custom calls run again and state defaults retain fresh-container semantics', () => {
  const {bridge,parser,library} = runtime();
  let calls = 0;
  const context = {getState:()=>null,resolveRef:()=>null,functions:{
    Probe:{params:{type:'object',properties:{}},fn(){ return ++calls; }},
  }};
  let result = parser.push('$items=[1,2]\nroot=Stack([Box(@Probe()),tail])\ntail=Box("');
  let defaults = result.stateDeclarations.$items;
  assert(Array.isArray(defaults));
  for (let index = 0; index < 10; index++) {
    result = parser.push('x');
    accepted(bridge,result);
    assert.notEqual(result.stateDeclarations.$items,defaults);
    defaults = result.stateDeclarations.$items;
    const outcome = bridge.boundedRoot(result,context,library,null,[]);
    assert.equal(outcome.error,undefined);
    assert.equal(outcome.limitExceeded,false);
    assert.equal(calls,index+1);
    assert.equal(outcome.value.props.children[0].props.value,index+1);
  }
});

test('each pass repeats its diagnostics in the same order while aliases report once', () => {
  const {bridge,parser} = runtime();
  let result = parser.push('root=Stack([a,a,b,tail])\na=Missing("a")\nb=Missing("b")\ntail=Box("');
  const expected = JSON.stringify(result.meta.errors);
  assert.deepEqual(Array.from(result.meta.errors).filter(error=>error.code==='unknown-component').map(error=>error.statementId),['a','b']);
  for (let index = 0; index < 10; index++) {
    result = parser.push('x');
    accepted(bridge,result);
    assert.equal(JSON.stringify(result.meta.errors),expected);
  }
});

test('fence replacement and set reset the completed prefix and source budget accounting', () => {
  const {bridge,parser} = runtime();
  assert.equal(accepted(bridge,parser.push('root=Box("outside")\n')).props.value,'outside');
  assert.equal(accepted(bridge,parser.push('```openui\nroot=Box("inside")\n')).props.value,'inside');
  assert.equal(accepted(bridge,parser.push('```\nfooter',true)).props.value,'inside');
  const large = 'root=Box("ok")\n' + Array.from({length:4096},(_,index)=>'v'+index+'=0').join('\n');
  assert.equal(bridge.nativeBudgetExceeded(parser.set(large,true)),true);
  const reset = parser.set('root=Box("reset")',true);
  assert.equal(accepted(bridge,reset).props.value,'reset');
  assert.equal(reset.meta.statementCount,1);
});
