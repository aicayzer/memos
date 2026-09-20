import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { expect, test } from 'vitest'
import { roundTrip } from './harness'

const fixture = readFileSync(resolve(__dirname, '../fixtures/dialect.md'), 'utf8')

test('the dialect fixture is written back byte for byte', async () => {
  expect(await roundTrip(fixture)).toBe(fixture)
})

test('a memo written back is stable on a second pass', async () => {
  const once = await roundTrip(fixture)
  expect(await roundTrip(once)).toBe(once)
})

const variants: Array<[string, string, string]> = [
  ['underscore emphasis', '_italic_ and __bold__\n', '*italic* and **bold**\n'],
  ['star bullets', '* one\n* two\n', '- one\n- two\n'],
  ['two-space hard break', 'first  \nsecond\n', 'first\\\nsecond\n'],
  ['star rule', '***\n', '---\n'],
  ['bare url', 'See https://example.com now\n', 'See <https://example.com> now\n'],
  ['indented code stays fenced', '    code\n', '```\ncode\n```\n'],
  ['heading with closing marks', '## Title ##\n', '## Title\n'],
]

for (const [name, input, canonical] of variants) {
  test(`non-canonical input is read and written in canonical form: ${name}`, async () => {
    expect(await roundTrip(input)).toBe(canonical)
  })
}
