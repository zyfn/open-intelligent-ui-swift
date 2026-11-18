// Explicit, source-checked fixes at the native bridge boundary. The original
// core remains the oracle for ordinary values, action contents and validation.
import { replaceOnce } from './compat.mjs';

// The Swift transport probe identifies the first real frame outside raw Lang
// strings/comments. Keep the official selection algorithm, but do not let it
// reinterpret markers inside that protected prefix. The public message API
// calls the same implementation with its original unrestricted boundary.
export function messageBoundary(source) {
  source = replaceOnce(source,
    'export function parseMessage(raw: string, { streaming }: ParseMessageOptions = {}): ParsedMessage {',
    `export function parseMessage(raw: string, options: ParseMessageOptions = {}): ParsedMessage {
  return nativeParseMessage(raw, options);
}

export function nativeParseMessage(raw: string, { streaming }: ParseMessageOptions = {}, protectedPrefix = 0): ParsedMessage {`);
  source = replaceOnce(source,
    'const held = streaming && last !== "" && PREFIX.startsWith(last);',
    'const held = streaming && nl + 1 >= protectedPrefix && last !== "" && PREFIX.startsWith(last);');
  source = replaceOnce(source,
    '  let text = raw.replace(RETRY, "$1\\n");',
    `  // Include exactly one preceding unit so a mid-line first content frame
  // keeps the official retry newline, without scanning the protected prefix.
  const retryStart = Math.max(0, protectedPrefix - 1);
  let text = raw.slice(0, retryStart) + raw.slice(retryStart).replace(RETRY, "$1\\n");`);
  source = replaceOnce(source,
    'if (cut && `${PREFIX}content`.startsWith(cut[1]))',
    'if (cut && cut.index + 1 >= protectedPrefix && `${PREFIX}content`.startsWith(cut[1]))');
  source = replaceOnce(source,
    'const held = streaming && last !== "" && (last.startsWith(PREFIX) || PREFIX.startsWith(last));',
    'const held = streaming && text.lastIndexOf("\\n") + 1 >= protectedPrefix && last !== "" && (last.startsWith(PREFIX) || PREFIX.startsWith(last));');
  source = replaceOnce(source,
    '  for (const [i, line] of lines.entries()) {\n    const match = MARKER.exec(line.replace(/\\r$/, ""));',
    `  let lineOffset = 0;
  for (const [i, line] of lines.entries()) {
    const match = lineOffset >= protectedPrefix ? MARKER.exec(line.replace(/\\r$/, "")) : null;
    lineOffset += line.length + 1;`);
  return source;
}

export function actionProvenance(source, capturesPath) {
  source = replaceOnce(source,
    'if (isStep(node.name)) return evaluateActionCall(node, context);',
    'if (isStep(node.name)) return nativeCorePlan(evaluateActionCall(node, context));');
  source = replaceOnce(source,
    'if (missesRequired(args, def.params)) return { steps: [] };',
    'if (missesRequired(args, def.params)) return nativeCorePlan({ steps: [] });');
  source = replaceOnce(source,
    'if (params === INVALID) return { steps: [] };',
    'if (params === INVALID) return nativeCorePlan({ steps: [] });');
  source = replaceOnce(source,
    '        return { steps: [step] };',
    '        return nativeCorePlan({ steps: [step] });');
  source = replaceOnce(source,
    '  return plan.steps.every(own) ? plan : { ...plan, steps: plan.steps.filter(own) };',
    '  return nativeCopyCorePlan(plan, plan.steps.every(own) ? plan : { ...plan, steps: plan.steps.filter(own) });');
  return `import { corePlan as nativeCorePlan, copyCorePlan as nativeCopyCorePlan } from ${JSON.stringify(capturesPath)};\n` + source;
}

export function propActionProvenance(source, capturesPath) {
  // Data is allowed to contain a `steps` field, including business records that
  // happen to resemble action steps. Only evaluated calls/native plans take the
  // deferred-action path. Explicit DSL Action(...) still applies ownSteps.
  source = replaceOnce(source,
    '  return isActionPlan(result) ? ownSteps(result) : result;',
    '  return nativeIsRuntimePlan(result) && !nativeIsNativePlan(result) ? ownSteps(result) : result;');
  source = replaceOnce(source,
    '  if (isActionPlan(value)) return value;',
    '  if (nativeIsRuntimePlan(value)) return value;');
  return `import { isRuntimePlan as nativeIsRuntimePlan, isNativePlan as nativeIsNativePlan } from ${JSON.stringify(capturesPath)};\n` + source;
}

export function validationOwnKeys(source) {
  return replaceOnce(source,
    '    const validator = customValidators?.[rule.type] ?? builtInValidators[rule.type];',
    `    const custom = customValidators && Object.prototype.hasOwnProperty.call(customValidators, rule.type)
      ? customValidators[rule.type] : undefined;
    const validator = custom ?? (Object.prototype.hasOwnProperty.call(builtInValidators, rule.type)
      ? builtInValidators[rule.type] : undefined);`);
}

// Request ownership and shared-consumer retirement are independent of budgets.
export function queryLifecycle(source) {
  // A request belongs to its existing cache entry. Its first statement can
  // disappear while another statement still consumes the same request; a
  // newly created entry with the same key must never receive old completion.
  source = replaceOnce(source, '    q.loading = true;\n    rebuildSnapshot();', `    const isCurrent = () => {
      if (disposed || cache.get(fetchKey) !== entry) return false;
      if (queries.get(statementId) === q && q.cacheKey === fetchKey) return true;
      for (const current of queries.values()) if (current.cacheKey === fetchKey) return true;
      return false;
    };
    for (const current of queries.values()) if (current.cacheKey === fetchKey) current.loading = true;
    rebuildSnapshot();`);
  source = replaceOnce(source,
    'const data = await toolProvider.callTool(toolName, (args as Record<string, unknown>) ?? {});',
    `const data = await (toolProvider.callTool as any)(toolName, (args as Record<string, unknown>) ?? {},
        isCurrent);`);
  source = replaceOnce(source, `      if (disposed) return;
      // Stale: the query was removed or its key changed
      const current = queries.get(statementId);
      if (!current || current.cacheKey !== fetchKey) {
        entry.inFlight = false;
        return;
      }

      entry.data = data ?? null;
      entry.failed = false;
      current.everFetched = true;
      for (const q of queries.values()) if (q.cacheKey === fetchKey) q.error = undefined;

      // Clear prevCacheKey first so cleanup does not see it as in use
      if (current.prevCacheKey && current.prevCacheKey !== fetchKey) {
        const prevKey = current.prevCacheKey;
        current.prevCacheKey = undefined;
        cleanupCacheEntry(prevKey);
      }`, `      if (!isCurrent()) return;
      entry.data = data ?? null;
      entry.failed = false;
      const previousKeys = new Set<string>();
      for (const current of queries.values()) {
        if (current.cacheKey !== fetchKey) continue;
        const previousKey = acceptCacheResult(current);
        if (previousKey) previousKeys.add(previousKey);
      }
      for (const key of previousKeys) cleanupCacheEntry(key);`);
  source = replaceOnce(source, '    } catch (err) {\n      const failure =',
    '    } catch (err) {\n      if (!isCurrent()) return;\n      const failure =');
  source = replaceOnce(source, `    } finally {
      entry.inFlight = false;
      const current = queries.get(statementId);
      if (current && current.cacheKey === fetchKey) {
        current.loading = false;
        if (rebuildSnapshot()) notify();
        if (current.needsRefetch) {
          current.needsRefetch = false;
          executeFetch(current.cacheKey, statementId);
        }
      } else {
        if (rebuildSnapshot()) notify();
      }
      reevaluateReaders();
    }`, `    } finally {
      entry.inFlight = false;
      if (!isCurrent()) return;
      let refetch = false;
      for (const current of queries.values()) {
        if (current.cacheKey !== fetchKey) continue;
        current.loading = false;
        refetch ||= current.needsRefetch;
        current.needsRefetch = false;
      }
      if (rebuildSnapshot()) notify();
      // A synchronous listener can retire this entry or start its refresh.
      if (!isCurrent()) return;
      if (refetch && !entry.inFlight) {
        for (const [sid, current] of queries) {
          if (current.cacheKey !== fetchKey) continue;
          executeFetch(fetchKey, sid);
          break;
        }
      }
      reevaluateReaders();
    }`);
  source = replaceOnce(source, '  /** Remove a cache entry if no query references it. */', `  /** Accept current data, whether a request just finished or the key was cached. */
  function acceptCacheResult(q: QueryEntry): string | undefined {
    q.everFetched = true;
    q.error = undefined;
    const previousKey = q.prevCacheKey;
    q.prevCacheKey = undefined;
    return previousKey && previousKey !== q.cacheKey ? previousKey : undefined;
  }

  /** Remove a cache entry if no query references it. */`);
  // A later node in the same patch can adopt a released key. Decide whether
  // it is unused only after all current/previous key references are updated.
  source = replaceOnce(source,
    '    const activeIds = new Set(queryNodes.map((n) => n.statementId));',
    '    const activeIds = new Set(queryNodes.map((n) => n.statementId));\n    const cacheKeysToClean = new Set<string>();');
  source = replaceOnce(source, `        queries.delete(sid);
        cleanupCacheEntry(q.cacheKey);
        if (q.prevCacheKey) cleanupCacheEntry(q.prevCacheKey);`, `        queries.delete(sid);
        cacheKeysToClean.add(q.cacheKey);
        if (q.prevCacheKey) cacheKeysToClean.add(q.prevCacheKey);`);
  source = replaceOnce(source, `        if (existing.cacheKey !== cacheKey) {
          existing.prevCacheKey = existing.cacheKey;`, `        if (existing.cacheKey !== cacheKey) {
          if (existing.prevCacheKey) cacheKeysToClean.add(existing.prevCacheKey);
          existing.prevCacheKey = existing.cacheKey;`);
  source = replaceOnce(source, `      q.waiting = node.waitFor?.some((dep) => getData(dep) === undefined) ?? false;
      if (q.waiting) continue;

      const entry = cache.get(cacheKey);`, `      q.waiting = node.waitFor?.some((dep) => getData(dep) === undefined) ?? false;
      const entry = cache.get(cacheKey);
      q.loading = entry?.inFlight ?? false;
      if (entry?.data !== undefined && !entry.failed) {
        const previousKey = acceptCacheResult(q);
        if (previousKey) cacheKeysToClean.add(previousKey);
      }
      if (q.waiting) continue;`);
  source = replaceOnce(source, `        q.refreshInterval = newInterval;
      }
    }

    if (rebuildSnapshot()) notify();`, `        q.refreshInterval = newInterval;
      }
    }

    for (const key of cacheKeysToClean) cleanupCacheEntry(key);
    if (rebuildSnapshot()) notify();`);
  // dispose owns its terminal snapshot; it must not rely on a retired
  // request's finally to make getSnapshot agree with isLoading.
  source = replaceOnce(source, '    mutations.clear();\n  }\n\n  return {',
    '    mutations.clear();\n    rebuildSnapshot();\n  }\n\n  return {');
  return source;
}
