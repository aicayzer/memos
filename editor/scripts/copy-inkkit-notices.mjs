import { copyFile, mkdir, readFile, writeFile } from 'node:fs/promises'

const packageDist = new URL('.', import.meta.resolve('@aicayzer/inkkit/core'))
await mkdir('dist/licenses', { recursive: true })
for (const [source, destination] of [
  ['../LICENSE', 'INKKIT-LICENSE.txt'],
  ['../NOTICE', 'INKKIT-NOTICE.txt'],
  ['THIRD-PARTY-NOTICES.txt', 'INKKIT-THIRD-PARTY-NOTICES.txt'],
]) {
  await copyFile(new URL(source, packageDist), `dist/licenses/${destination}`)
}
await copyFile('dist/HOST-THIRD-PARTY-NOTICES.md', 'dist/licenses/HOST-THIRD-PARTY-NOTICES.md')

const { version } = JSON.parse(await readFile(new URL('../package.json', packageDist), 'utf8'))
await writeFile('dist/editor-version.json', JSON.stringify({ editorVersion: version }))
