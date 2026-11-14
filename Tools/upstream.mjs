// Build-time dependency acquisition only. SwiftPM consumers use committed
// resources and never need Node, Git, npm or a network fetch at application time.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
export const lock = JSON.parse(readFileSync(join(here, 'upstream.json'), 'utf8'));
if (lock.repository !== 'https://github.com/thesysdev/openui.git') {
  throw Error('Review the upstream repository before changing the trust boundary');
}
const revisions = new Set([lock.core.revision, lock.richText.revision, lock.referenceCatalog.revision]);
for (const revision of revisions) {
  if (!/^[0-9a-f]{40}$/.test(revision)) throw Error('Upstream revisions must be complete immutable commit IDs');
}
const temporary = mkdtempSync(join(tmpdir(), 'openui-upstream-'));
process.once('exit', () => rmSync(temporary, { recursive: true, force: true }));
let repository, prepared;
const exec = (cwd, args, options = {}) => execFileSync('git', args, {
  cwd, maxBuffer: 128 * 1024 * 1024, timeout: 180_000, ...options,
});

function dependency(revision) {
  if (!revisions.has(revision)) throw Error(`Unpinned upstream revision: ${revision}`);
  if (!repository) {
    // An optional pre-fetched repository supports offline CI. Contents still
    // have to match the pinned commit/tree; it is never modified by this tool.
    if (process.env.OPENUI_UPSTREAM_GIT) repository = resolve(process.env.OPENUI_UPSTREAM_GIT);
    else {
      repository = join(temporary, 'official.git');
      exec(temporary, ['init', '--bare', repository], { stdio: 'ignore' });
    }
  }
  try { exec(repository, ['cat-file', '-e', `${revision}^{commit}`], { stdio: 'ignore' }); }
  catch {
    if (process.env.OPENUI_UPSTREAM_GIT) throw Error(`Offline upstream input is missing ${revision}`);
    exec(repository, ['fetch', '--no-tags', '--depth=1', '--filter=blob:none', lock.repository, revision], { stdio: 'inherit' });
  }
  return repository;
}
function checkedPath(path) {
  if (!path || path.startsWith('/') || path.split('/').some(part => !part || part === '.' || part === '..') || /[\\\0\r\n]/.test(path)) {
    throw Error('Invalid upstream source path');
  }
  return path;
}
export function upstreamFile(revision, path) {
  return exec(dependency(revision), ['show', `${revision}:${checkedPath(path)}`], { encoding: 'utf8' });
}
export function upstreamFiles(revision, path) {
  return exec(dependency(revision), ['ls-tree', '-r', '--name-only', revision, '--', checkedPath(path)], { encoding: 'utf8' })
    .trim().split('\n').filter(Boolean);
}
export function prepareCoreSource() {
  if (prepared) return prepared;
  const repo = dependency(lock.core.revision);
  const tree = exec(repo, ['rev-parse', `${lock.core.revision}:packages/lang-core`], { encoding: 'utf8' }).trim();
  if (tree !== lock.core.originalTree) throw Error('Official core tree does not match the reviewed lock');
  const patchPath = join(here, checkedPath(lock.core.sourcePatch));
  const patch = readFileSync(patchPath);
  if (createHash('sha256').update(patch).digest('hex') !== lock.core.sourcePatchSHA256) {
    throw Error('Native signature patch differs from the reviewed lock');
  }
  const root = mkdtempSync(join(temporary, 'source-'));
  const archive = exec(repo, ['archive', '--format=tar', lock.core.revision, 'LICENSE', 'tsconfig.json', 'packages/lang-core']);
  execFileSync('tar', ['-xf', '-', '-C', root], { input: archive, timeout: 30_000 });
  exec(root, ['init', '--quiet']);
  exec(root, ['apply', '--check', patchPath]);
  exec(root, ['apply', patchPath]);
  exec(root, ['add', '-f', 'LICENSE', 'packages/lang-core']);
  const stagedTree = exec(root, ['write-tree'], { encoding: 'utf8' }).trim();
  if (!stagedTree) throw Error('Empty source tree');
  const adapted = exec(root, ['rev-parse', `${stagedTree}:packages/lang-core`], { encoding: 'utf8' }).trim();
  if (adapted !== lock.core.adaptedTree) throw Error(`Native compatibility source tree differs: ${adapted}`);
  // This local commit only provides HEAD-based cleanliness checks to existing
  // generators. It is not represented as an official upstream commit.
  exec(root, ['-c', 'user.name=OpenUI build input', '-c', 'user.email=build-input@example.invalid',
    'commit', '--quiet', '-m', 'Verified immutable upstream snapshot plus explicit native signature patch']);
  prepared = root;
  return root;
}
export function coreSourcePlugin(root) {
  return {
    name: 'pinned-official-core-source',
    setup(build) {
      build.onResolve({ filter: /^@openui\/core-source(?:\/|$)/ }, ({ path }) => {
        const suffix = path === '@openui/core-source' ? 'index' : path.slice('@openui/core-source/'.length);
        checkedPath(suffix);
        const base = join(root, 'packages/lang-core/src', suffix);
        for (const candidate of [base, base + '.ts', join(base, 'index.ts')]) {
          if (existsSync(candidate)) return { path: candidate };
        }
        throw Error(`Pinned core does not contain ${path}`);
      });
    },
  };
}
