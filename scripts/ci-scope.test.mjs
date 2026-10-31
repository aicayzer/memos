import assert from 'node:assert/strict'
import { test } from 'node:test'
import { needsBuild } from './ci-scope.mjs'

test('prose, design, records and ignore rules need no build', () => {
  assert.equal(needsBuild(['README.md', 'marfa/notes/a.md', '.gitignore']), false)
  assert.equal(needsBuild(['DEVELOPMENT.md', 'design/icon.svg']), false)
})

test('any source, workflow or script change keeps the lanes', () => {
  assert.equal(needsBuild(['README.md', 'App/MainView.swift']), true)
  assert.equal(needsBuild(['.github/workflows/ci.yml']), true)
  assert.equal(needsBuild(['scripts/ci-scope.mjs']), true)
  assert.equal(needsBuild(['editor/src/main.ts']), true)
})

test('an empty diff keeps the lanes', () => {
  assert.equal(needsBuild([]), true)
})
