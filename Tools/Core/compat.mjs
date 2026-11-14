// Explicit dependency export compatibility, shared-core corrections and budgets.
// Every replacement is checked against the pinned source; upgrades must review it.
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

export const zodJSONSchemaCompatibility = Object.freeze({
  package: 'zod',
  version: '4.6.7',
  module: 'v4/core/to-json-schema.js',
  sourceSHA256: '85b883eb8f05e9f060c71a39fce7df9345b566af29d5bc9c8fa477fe616a051d',
  transformedSHA256: '38c767e92b86e8c6808531ca3c43f58075284af2eb6ca5503f02a0ef1efb26ec',
  reason: 'Preserve established anyOf union spelling, nesting and key order; Zod parsing, validation and collection security limits are unchanged.',
});

// Zod 4.6.7 introduced a final JSON Schema compaction pass after its public
// override callback. Disabling just that pass retains the existing schema
// contract, including nested/nullable unions, without attempting a lossy
// type-array rewrite or changing the security-fixed validators.
export function zodJSONSchemaCompatibilityPlugin() {
  const digest = source => createHash('sha256').update(source).digest('hex');
  let loaded = 0;
  return {
    name: 'native-zod-json-schema-unions',
    setup(build) {
      build.onStart(() => { loaded = 0; });
      build.onLoad({ filter: /\/zod\/v4\/core\/to-json-schema\.js$/, namespace: 'file' }, args => {
        const version = JSON.parse(readFileSync(join(dirname(args.path), '../../package.json'), 'utf8')).version;
        const source = readFileSync(args.path, 'utf8');
        if (version !== zodJSONSchemaCompatibility.version || digest(source) !== zodJSONSchemaCompatibility.sourceSHA256)
          throw Error('Review the pinned Zod JSON Schema export compatibility before upgrading');
        const contents = replaceOnce(source,
          `        if (ctx.target !== "openapi-3.0") {
            for (const entry of ctx.seen.entries()) {
                compactTypeUnion(entry[1].def ?? entry[1].schema);
            }
        }`,
          '        // Preserve the established native JSON Schema union representation.');
        if (digest(contents) !== zodJSONSchemaCompatibility.transformedSHA256)
          throw Error('Zod JSON Schema compatibility transform differs from its reviewed digest');
        loaded++;
        return { contents, loader: 'js' };
      });
      build.onEnd(result => {
        if (!result.errors.length && loaded !== 1)
          return { errors: [{ text: `Expected exactly one pinned Zod JSON Schema emitter, found ${loaded}` }] };
      });
    },
  };
}

export function replaceOnce(source, before, after) {
  if (source.split(before).length !== 2)
    throw Error(
      'Pinned compatibility patch no longer matches: ' + before.slice(0, 90),
    );
  return source.replace(before, after);
}
export function serializer(source) {
  const patches = [
    ['_side: "left" | "right",', 'side: "left" | "right",'],
    [
      'if (child.k !== "BinOp") return inner;',
      'if (child.k === "Ternary" || child.k === "Assign") return `(${inner})`;\n  if (child.k !== "BinOp") return inner;',
    ],
    [
      'if (childPrec < parentPrec) return `(${inner})`;',
      'if (childPrec < parentPrec || (side === "right" && childPrec === parentPrec)) return `(${inner})`;',
    ],
    [
      'return `${node.op}${serializeASTNode(node.operand, calls)}`;',
      'return `${node.op}${tight(node.operand, calls)}`;',
    ],
    [
      'return `${serializeASTNode(node.cond, calls)} ? ${serializeASTNode(node.then, calls)} : ${serializeASTNode(node.else, calls)}`;',
      'return `${node.cond.k === "Ternary" || node.cond.k === "Assign" ? "(" + serializeASTNode(node.cond, calls) + ")" : serializeASTNode(node.cond, calls)} ? ${serializeASTNode(node.then, calls)} : ${serializeASTNode(node.else, calls)}`;',
    ],
    [
      'return `${serializeASTNode(node.obj, calls)}.${node.field}`;',
      'return `${tight(node.obj, calls)}[${JSON.stringify(node.field)}]`;',
    ],
    [
      'return `${serializeASTNode(node.obj, calls)}[${serializeASTNode(node.index, calls)}]`;',
      'return `${tight(node.obj, calls)}[${serializeASTNode(node.index, calls)}]`;',
    ],
    [
      '`${k}: ${serializeASTNode(v, calls)}`',
      '`${key(k)}: ${serializeASTNode(v, calls)}`',
    ],
    [
      '`${k}: ${serializeValue(v, paramMap, collector)}`',
      '`${key(k)}: ${serializeValue(v, paramMap, collector)}`',
    ],
  ];
  for (const [before, after] of patches)
    source = replaceOnce(source, before, after);
  return (
    source +
    '\nfunction key(k:string){return /^[A-Za-z_][A-Za-z0-9_]*$/.test(k)?k:JSON.stringify(k);}\nfunction tight(n:ASTNode,c:ReadonlyMap<string,CallDef>){const text=serializeASTNode(n,c);return ["BinOp","UnaryOp","Ternary","Assign"].includes(n.k)?"("+text+")":text;}\n'
  );
}
export function materializer(source) {
  source = replaceOnce(
    source,
    'export function materializeValue(node: ASTNode, ctx: MaterializeCtx): unknown {',
    `export function materializeValue(node: ASTNode, ctx: MaterializeCtx): unknown {
  return nativeBudget(ctx,()=>nativeMaterializeValue(node,ctx),null);
}
function nativeMaterializeValue(node: ASTNode, ctx: MaterializeCtx): unknown {`,
  );
  source = replaceOnce(
    source,
    `): ASTNode {
  switch (node.k) {`,
    `): ASTNode {
  return nativeBudget(ctx,()=>nativeMaterializeExpr(node,ctx,scopedRefs),{k:"Null"});
}
function nativeMaterializeExpr(node:ASTNode,ctx:MaterializeCtx,scopedRefs:ReadonlySet<string>):ASTNode {
  switch (node.k) {`,
  );
  return (
    source +
    `
function nativeBudget<T>(ctx:MaterializeCtx,body:()=>T,fallback:T):T {
 const state=ctx as MaterializeCtx & {nativeDepth?:number,nativeNodes?:number,nativeLimit?:boolean};
 state.nativeDepth=(state.nativeDepth??0)+1;state.nativeNodes=(state.nativeNodes??0)+1;
 try{
  if(state.nativeDepth>256||state.nativeNodes>100000){
   if(!state.nativeLimit){state.nativeLimit=true;ctx.errors.push({source:"parser",code:"parse-exception",message:"Materialization limit exceeded (256 levels or 100000 nodes).",statementId:ctx.currentStatementId});}
   return fallback;
  }
  return body();
 }finally{state.nativeDepth--;}
}
`
  );
}
