import assert from 'node:assert/strict';

// Every scenario runs against both the pristine pinned official module and the
// actual shipped JavaScriptCore resource. Explicit outcomes keep a shared
// regression from being hidden by comparing two equally wrong traces.
export async function verifyLang111({official, native, bridge, schema, digest}) {
  const cases = [];
  const plain = value => JSON.parse(JSON.stringify(value));
  const settle = () => new Promise(resolve => setImmediate(resolve));
  const library = {components: {}, toJSONSchema: () => schema};
  const parse = (core, source) => core.createParser(schema).parse(source);
  const clean = result => assert.deepEqual(plain(result.meta.errors), []);
  const context = (store, manager) => ({
    getState: name => store.get(name) ?? null,
    resolveRef: name => manager?.getResult(name) ?? null,
  });
  const render = (core, result, store) => {
    const errors = [];
    const tree = core.evaluateRoot(result, {ctx: context(store), library, store, errors});
    assert.deepEqual(plain(errors), []);
    return tree;
  };
  async function compare(id, scenario) {
    const expected = await scenario(official);
    const actual = await scenario(native);
    assert.equal(digest(actual), digest(expected), 'Lang 1.1: ' + id);
    cases.push({id, expected: digest(expected)});
  }
  function controlled(core, source) {
    const result = parse(core, source);
    const store = core.createStore();
    store.initialize(result.stateDeclarations, {});
    const calls = [], pending = [];
    const manager = core.createQueryManager({callTool: (name, args) => {
      calls.push({name, args: plain(args)});
      return new Promise((resolve, reject) => pending.push({name, resolve, reject}));
    }});
    const ctx = context(store, manager);
    return {result, store, calls, pending, manager, ctx,
      evaluate: options => manager.evaluateStatements(result.queryStatements, ctx, options),
      snapshot: () => digest(manager.getSnapshot()),
      resolve: async (name, value) => {
        const next = pending.shift();
        assert.equal(next?.name, name);
        next.resolve(value);
        await settle();
      },
    };
  }

  for (const [name, expression, value] of [
    ['round-list', '@Round([1.4,2.6,-1.5])', [1,3,-1]],
    ['round-list-decimals', '@Round([1.25,2.75],1)', [1.3,2.8]],
    ['abs-list', '@Abs([-2,0,3])', [2,0,3]],
    ['floor-list', '@Floor([1.9,-1.1,2])', [1,-2,2]],
    ['ceil-list', '@Ceil([1.1,-1.9,2])', [2,-1,2]],
  ]) {
    await compare(name, core => {
      const result = parse(core, 'root=Box(' + expression + ')');
      clean(result);
      const actual = render(core, result, core.createStore()).props.value;
      assert.deepEqual(plain(actual), value, name);
      return {parsed: result, value: actual};
    });
  }

  await compare('expression-state-defaults', core => {
    const result = parse(core, '$n=2\n$total=$n*3\n$nested=[1+2,{x:4*2}]\nroot=Box([$n,$total,$nested])');
    clean(result);
    assert.deepEqual(plain(result.stateDeclarations), {$n:2, $total:6, $nested:[3,{x:8}]});
    const store = core.createStore();
    store.initialize(result.stateDeclarations, {$n:10});
    const first = render(core, result, store).props.value;
    assert.deepEqual(plain(first), [10,6,[3,{x:8}]], 'Computed defaults must not become reactive formulas');
    store.set('$n', 20);
    assert.equal(store.get('$total'), 6);
    return {defaults: result.stateDeclarations, first, state: store.getSnapshot()};
  });

  await compare('state-defaults-do-not-run-custom-code', core => {
    const customSchema = {...schema, functions: {
      Next: {params: {type:'object',properties:{value:{type:'number'}},required:['value']}},
    }};
    const result = core.createParser(customSchema).parse('$n=2\n$custom=@Next(4)\n$action=@Set($n,9)\nroot=Box([$custom,$action])');
    clean(result);
    assert.deepEqual(plain(result.stateDeclarations), {$n:2, $custom:null, $action:null});
    return result;
  });

  for (const [id, source, value] of [
    ['inline-fence-mention', 'Mention ```openui``` inline.\nroot=Box("kept")', 'kept'],
    ['fence-opener-code', '```openui root=Box("opener")\n```', 'opener'],
    ['helper-js-fence', '```js\nconsole.log("helper");\n```\n```openui\nroot=Box("body")\n```', 'body'],
    ['skip-openui-js-fence', '```openui-js\nroot=Box("ignored")\n```\n```openui\nroot=Box("body")\n```', 'body'],
    ['stray-closing-fence', 'root=Box("stray")\n```', 'stray'],
    ['fence-line-in-string', 'root=Box("hello\n```\nworld")', 'hello\n```\nworld'],
  ]) {
    await compare(id, core => {
      const result = parse(core, source);
      clean(result);
      assert.equal(result.root.props.value, value);
      return result;
    });
  }

  await compare('immutable-stream-snapshots', core => {
    const stream = core.createStreamingParser(schema);
    const results = [], snapshots = [];
    for (const chunk of ['root=Stack([head,tail])\n', 'head=Box("fixed")\n', 'tail=Box("a', 'b', 'c")']) {
      results.push(stream.push(chunk));
      snapshots.push(digest(results.at(-1)));
      for (let i=0; i<results.length; i++) {
        assert.equal(digest(results[i]), snapshots[i], 'Later chunks must not mutate earlier parse results');
      }
    }
    const final = stream.getResult(true);
    clean(final);
    assert.equal(final.root.props.children[1].props.value, 'abc');
    for (let i=0; i<results.length; i++) assert.equal(digest(results[i]), snapshots[i]);
    return {snapshots, final};
  });

  await compare('merge-multiline-ternary', core => {
    const source = '$show=true\nroot=$show\n ? Box("yes")\n : Box("no")';
    const merged = core.mergeStatements(source, '$show=false');
    const result = parse(core, merged);
    clean(result);
    const store = core.createStore();
    store.initialize(result.stateDeclarations, {});
    assert.equal(render(core, result, store).props.value, 'no');
    return {merged, result};
  });

  await compare('query-alias-dependency-chain', async core => {
    const h = controlled(core, 'root=Box(details)\n$region="west"\nfilters={region:$region}\nfirst=Query("ids",filters,[])\nalias=first\nargs={ids:alias}\ndetails=Query("details",args,[])');
    try {
      clean(h.result);
      assert.deepEqual(plain(h.result.queryStatements[0].deps), ['$region']);
      assert.deepEqual(plain(h.result.queryStatements[1].waitFor), ['first']);
      const snapshots = [];
      h.evaluate();
      assert.deepEqual(h.calls, [{name:'ids',args:{region:'west'}}]);
      assert.equal(h.manager.isLoading('details'), true, 'A reader waits on a loading query');
      snapshots.push(h.snapshot());
      await h.resolve('ids', ['a']);
      assert.deepEqual(h.calls.at(-1), {name:'details',args:{ids:['a']}});
      snapshots.push(h.snapshot());
      await h.resolve('details', [{id:'a',score:7}]);
      snapshots.push(h.snapshot());
      h.store.set('$region', 'east');
      h.evaluate();
      assert.equal(h.calls.length, 3);
      assert.deepEqual(h.calls.at(-1), {name:'ids',args:{region:'east'}});
      snapshots.push(h.snapshot());
      await h.resolve('ids', ['b']);
      assert.deepEqual(h.calls.at(-1), {name:'details',args:{ids:['b']}});
      await h.resolve('details', [{id:'b',score:9}]);
      snapshots.push(h.snapshot());
      h.evaluate();
      assert.equal(h.calls.length, 4, 'Unchanged inputs reuse settled query results');
      h.manager.invalidate(['first']);
      await h.resolve('ids', ['c']);
      assert.deepEqual(h.calls.at(-1), {name:'details',args:{ids:['c']}});
      await h.resolve('details', [{id:'c',score:11}]);
      snapshots.push(h.snapshot());
      return {statements:h.result.queryStatements, calls:h.calls, snapshots};
    } finally { h.manager.dispose(); }
  });

  await compare('query-cycles-do-not-fetch', core => {
    const h = controlled(core, 'root=Box(c)\na=Query("first",{b:b},[])\nb=Query("second",{a:a},[])\nc=Query("third",{a:a},[])');
    try {
      assert.deepEqual(plain(h.result.meta.errors.map(e=>e.code)), ['query-cycle']);
      h.evaluate();
      assert.deepEqual(h.calls, []);
      assert.equal(h.manager.isAnyLoading(), false);
      return {errors:h.result.meta.errors, statements:h.result.queryStatements, snapshot:h.snapshot()};
    } finally { h.manager.dispose(); }
  });

  await compare('failed-query-requires-explicit-retry', async core => {
    const h = controlled(core, 'root=Box(q)\nq=Query("load",{id:1},{cached:false})');
    const previousError = console.error;
    try {
      clean(h.result);
      // Expected failures are asserted through the public diagnostic snapshot.
      console.error = () => {};
      h.evaluate();
      h.pending.shift().reject('controlled failure');
      await settle();
      const snapshots = [h.snapshot()];
      assert.equal(h.manager.getSnapshot().__openui_errors[0].code, 'tool-error');
      for (let i=0; i<3; i++) h.evaluate();
      assert.equal(h.calls.length, 1, 'Re-evaluation must not retry a failed cache entry');
      h.manager.invalidate(['q']);
      assert.equal(h.calls.length, 2);
      await h.resolve('load', {recovered:true});
      snapshots.push(h.snapshot());
      assert.deepEqual(plain(h.manager.getSnapshot().__openui_errors), []);
      h.evaluate();
      assert.equal(h.calls.length, 2);
      return {calls:h.calls, snapshots};
    } finally { console.error = previousError; h.manager.dispose(); }
  });

  await compare('query-host-extra-dependencies', async core => {
    const h = controlled(core, 'root=Box(q)\nq=Query("load",{id:1},[])');
    let account = 'first';
    try {
      const options = {extraDeps: name => {assert.equal(name,'load');return {account};}};
      h.evaluate(options);
      await h.resolve('load', ['first-account']);
      const snapshots = [h.snapshot()];
      account = 'second';
      h.evaluate(options);
      assert.equal(h.calls.length, 2, 'Host dependency changes invalidate an otherwise identical query');
      await h.resolve('load', ['second-account']);
      snapshots.push(h.snapshot());
      return {calls:h.calls, snapshots};
    } finally { h.manager.dispose(); }
  });

  await compare('mutation-arguments-resolve-statements', async core => {
    const h = controlled(core, '$n=3\nroot=Box("ready")\nm=Mutation(tool,args)\ntool="save"\nargs={count:$n+1,rows:@Each(items,item,item+10)}\nitems=[1,2]');
    try {
      clean(h.result);
      const mutation = h.result.mutationStatements[0];
      const name = core.evaluate(mutation.toolAST, h.ctx);
      h.manager.registerMutations([{statementId:'m',toolName:name}]);
      const first = core.evaluate(mutation.argsAST, h.ctx);
      assert.deepEqual(plain(first), {count:4,rows:[11,12]});
      const firstResult = h.manager.fireMutation('m', first);
      await h.resolve('save', {saved:4});
      assert.equal(await firstResult, true);
      h.store.set('$n', 9);
      const second = core.evaluate(mutation.argsAST, h.ctx);
      assert.deepEqual(plain(second), {count:10,rows:[11,12]});
      const secondResult = h.manager.fireMutation('m', second);
      await h.resolve('save', {saved:10});
      assert.equal(await secondResult, true);
      return {statement:mutation, calls:h.calls, snapshot:h.snapshot()};
    } finally { h.manager.dispose(); }
  });

  await compare('query-native-capture-bridge', async core => {
    const hostRecord = {id:'host-owned-record'};
    let value = 2;
    const calls = [];
    const manager = core.createQueryManager({callTool: async (name, args) => {
      assert.equal(args.record, hostRecord, 'The query bridge must retain opaque native value identity');
      calls.push({name, args:plain(args)});
      return {value:args.value};
    }});
    const captured = core === native ? bridge.capture(hostRecord) : {k:'Ref',n:'host-record'};
    const statements = [{
      statementId:'q',toolAST:{k:'Str',v:'load'},
      argsAST:{k:'Obj',entries:[['record',captured],['value',{k:'StateRef',n:'$n'}]]},
      defaultsAST:{k:'Arr',els:[]},refreshAST:null,deps:['$n'],complete:true,
    }];
    const ctx = {getState:()=>value,resolveRef:name=>{
      assert.equal(name,'host-record','Opaque captures must be resolved inside the native bridge');
      return hostRecord;
    }};
    const evaluate = () => core === native
      ? bridge.evaluateQueryStatements(manager, statements, ctx)
      : manager.evaluateStatements(statements, ctx);
    try {
      evaluate();
      await settle();
      value = 7;
      evaluate();
      await settle();
      assert.deepEqual(calls.map(call=>call.args.value),[2,7]);
      return {calls,snapshot:manager.getSnapshot()};
    } finally { manager.dispose(); }
  });

  return cases;
}

// Additional live comparisons keep the historical fixture corpus unchanged.
export function verifyMergeSourceCompatibility({ official, native, schema, digest }) {
  const cases = [
    ['ternary-blank-line-runs', '$show=true\nroot=$show' + '\n'.repeat(32)
      + '? Box("yes")' + '\n'.repeat(24) + ': Box("no")'],
    ['ordinary-blank-line-boundaries', 'value="yes"' + '\n'.repeat(32) + 'root=Box(value)'],
  ];
  function snapshot(core, source) {
    const result = core.createParser(schema).parse(source);
    assert.equal(result.meta.errors.length, 0);
    const store = core.createStore();
    store.initialize(result.stateDeclarations, {});
    const errors = [];
    const tree = core.evaluateRoot(result, { store, errors,
      library: { components: {}, toJSONSchema: () => schema },
      ctx: { getState: name => store.get(name) ?? null, resolveRef: () => null } });
    assert.equal(errors.length, 0);
    assert.equal(tree.props.value, 'yes');
    const stream = core.createStreamingParser(schema), snapshots = [];
    for (let offset = 0; offset < source.length; offset += 7) {
      snapshots.push(digest(stream.push(source.slice(offset, offset + 7))));
    }
    const final = stream.getResult(true);
    assert.equal(final.meta.errors.length, 0);
    return { result, snapshots, final };
  }
  for (const [id, source] of cases) {
    assert.equal(digest(snapshot(native, source)), digest(snapshot(official, source)), id);
  }
  return cases.length;
}
