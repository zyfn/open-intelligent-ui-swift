import { readFileSync } from 'node:fs';
import vm from 'node:vm';

// Share the shipped script, never its realm or mutable runtime state.
const script = readFileSync(process.env.OPENUI_NATIVE_CORE_JS
  ?? new URL('../../Sources/SwiftLang/Resources/lang-core.js', import.meta.url), 'utf8');

export function createNativeRuntime(globals = {}, options = { timeout: 5000 }) {
  const realm = vm.createContext({
    __utf8Encode: value => [...Buffer.from(value)],
    __utf8Decode: value => Buffer.from(value).toString('utf8'),
    ...globals,
  });
  vm.runInContext(script, realm, options);
  return realm;
}
