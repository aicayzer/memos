import { execFileSync } from 'node:child_process'
import { appendFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'

// Prose, design sources, personal records and ignore rules cannot change a
// build, so a pull request that touches only these runs no check lanes.
export function needsBuild(paths) {
  const inert = (path) =>
    /^(README|AGENTS|CLAUDE|DEVELOPMENT|RELEASING)\.md$/.test(path) ||
    path === 'LICENSE' ||
    path === '.gitignore' ||
    path.startsWith('marfa/') ||
    path.startsWith('design/') ||
    path.startsWith('.codex/')
  return paths.length === 0 || paths.some((path) => !inert(path))
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  const { EVENT, BASE, HEAD, GITHUB_OUTPUT } = process.env
  let build = true
  // Manual runs and missing history keep every lane.
  if (EVENT === 'pull_request' && BASE && !/^0+$/.test(BASE) && HEAD) {
    const paths = execFileSync(
      'git',
      ['diff', '--name-only', '--no-renames', '-z', `${BASE}...${HEAD}`],
      { encoding: 'utf8' },
    )
      .split('\0')
      .filter(Boolean)
    build = needsBuild(paths)
  }
  appendFileSync(GITHUB_OUTPUT, `build=${build}\n`)
}
