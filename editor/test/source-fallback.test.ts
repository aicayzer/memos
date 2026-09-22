import { expect, test, vi } from 'vitest'
import { SourceFallback } from '../src/source-fallback'

function fixture(canonical: string) {
  const formatted = {
    load: vi.fn(),
    reload: vi.fn(),
    canonicalMarkdown: () => canonical,
    markdown: () => null,
    focus: vi.fn(),
    find: vi.fn(),
    format: vi.fn(),
    insertPaths: vi.fn(),
    insertImages: vi.fn(),
    setKeymap: vi.fn(),
  }
  const root = document.createElement('div')
  const formattedRoot = document.createElement('div')
  root.append(formattedRoot)
  const changed = vi.fn()
  return {
    editor: new SourceFallback(formatted, formattedRoot, root, changed),
    formatted,
    formattedRoot,
    source: root.querySelector('textarea')!,
    changed,
  }
}

test('unfamiliar Markdown remains byte-for-byte intact until edited', () => {
  const original = '---\ncustom: [a, b]\n---\n<table><tr><td>Kept</td></tr></table>\n'
  const { editor, source, formattedRoot, changed } = fixture('Kept\n')
  editor.load(original, 7)
  expect(formattedRoot.hidden).toBe(true)
  expect(source.value).toBe(original)
  expect(editor.markdown()).toBeNull()
  source.value += 'Edited\n'
  source.dispatchEvent(new Event('input'))
  expect(editor.markdown()).toBe(original + 'Edited\n')
  expect(changed).toHaveBeenCalledWith(original + 'Edited\n', 7)
})

test('canonical memos retain the formatted editor', () => {
  const { editor, formattedRoot, formatted } = fixture('# Heading\n')
  editor.load('# Heading\n', 1)
  expect(formattedRoot.hidden).toBe(false)
  editor.format('bold')
  expect(formatted.format).toHaveBeenCalledWith('bold', undefined)
})

test('source reload retains selection and a new generation', () => {
  const { editor, source, changed } = fixture('normalized\n')
  editor.load('External text', 1)
  source.setSelectionRange(3, 3)
  editor.reload('External update', 2)
  expect(source.selectionStart).toBe(3)
  source.value += '!'
  source.dispatchEvent(new Event('input'))
  expect(changed).toHaveBeenLastCalledWith('External update!', 2)
})

test('opening CRLF source does not produce an edit and editing retains its line endings', () => {
  const { editor, source, changed } = fixture('canonical\n')
  editor.load('first\r\nsecond\r\n', 1)
  expect(editor.markdown()).toBeNull()
  source.value += 'third\n'
  source.dispatchEvent(new Event('input'))
  expect(editor.markdown()).toBe('first\r\nsecond\r\nthird\r\n')
  expect(changed).toHaveBeenLastCalledWith('first\r\nsecond\r\nthird\r\n', 1)
})

test('clearing find collapses the source selection without changing the memo', () => {
  const { editor, source, changed } = fixture('normalized\n')
  editor.load('External text', 1)
  editor.find('External')
  expect(source.selectionStart).toBe(0)
  expect(source.selectionEnd).toBe(8)
  editor.find('')
  expect(source.selectionStart).toBe(source.selectionEnd)
  expect(editor.markdown()).toBeNull()
  expect(changed).not.toHaveBeenCalled()
})

test('source find treats punctuation literally and wraps through matches', () => {
  const { editor, source } = fixture('normalized\n')
  editor.load('A [link] then [LINK]', 1)
  editor.find('[link]')
  expect(source.selectionStart).toBe(2)
  editor.find('[link]')
  expect(source.selectionStart).toBe(14)
  editor.find('[link]')
  expect(source.selectionStart).toBe(2)
  editor.find('absent')
  expect(source.selectionStart).toBe(source.selectionEnd)
  expect(editor.markdown()).toBeNull()
})
