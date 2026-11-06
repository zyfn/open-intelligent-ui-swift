import { functions } from "./Upstream";

const registry = Object.fromEntries(functions.map(f => [f.name, f]));
const RealDate = Date;
(globalThis as any).iuiFunctionNames = Object.keys(registry);
(globalThis as any).iuiCall = (name: string, raw: string, fixedNow: number | null) => {
  try {
    if (fixedNow !== null) {
      (globalThis as any).Date = class extends RealDate {
        constructor(...args: any[]) { super(...(args.length ? args : [fixedNow]) as [any]); }
        static now() { return fixedNow; }
      };
    }
    const definition = registry[name];
    if (!definition) throw new Error("Unknown function");
    return JSON.stringify(definition.fn(definition.params.parse(JSON.parse(raw)))) ?? "null";
  } catch { return "null"; }
  finally { (globalThis as any).Date = RealDate; }
};
