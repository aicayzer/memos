import { getMatchHighlights } from 'prosemirror-search'
import { expect, test } from 'vitest'
import { editorViewCtx } from '@milkdown/kit/core'
import type { Ctx } from '@milkdown/kit/ctx'
import { AllSelection, TextSelection } from '@milkdown/kit/prose/state'
import { Slice } from '@milkdown/kit/prose/model'
import { serialize } from '../src/dialect'
import { MemoEditor, type CaretState } from '../src/editor'

async function withMemoEditor<T>(
  markdown: string,
  run: (editor: MemoEditor, states: CaretState[]) => T,
  pasteImage: () => void = () => {},
) {
  const root = document.createElement('div')
  document.body.append(root)
  const states: CaretState[] = []
  const editor = await MemoEditor.mount(root, {
    changed() {},
    stateChanged(state) {
      states.push(state)
    },
    openLink() {},
    copy() {},
    pasteImage() {
      pasteImage()
    },
  })
  editor.load(markdown, 1)
  try {
    return run(editor, states)
  } finally {
    root.remove()
  }
}

function ctxOf(editor: MemoEditor): Ctx {
  return (editor as unknown as { editor: { ctx: Ctx } }).editor.ctx
}

function placeCaret(editor: MemoEditor, pos: number) {
  const view = ctxOf(editor).get(editorViewCtx)
  view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, pos)))
}

test('a loaded memo opens with the caret at its end', async () =>
  withMemoEditor('# Heading\n\nA line.\n', (editor) => {
    const { doc, selection } = ctxOf(editor).get(editorViewCtx).state
    expect(selection.empty).toBe(true)
    expect(selection.from).toBe(doc.content.size - 1)
  }))

test('a memo ending in a rule still opens with a caret', async () =>
  withMemoEditor('A line.\n\n---\n', (editor) => {
    expect(ctxOf(editor).get(editorViewCtx).state.selection.empty).toBe(true)
  }))

test('a loaded memo is not yet changed', async () =>
  withMemoEditor('# Heading\n\nA line.\n', (editor) => {
    expect(editor.markdown()).toBe(null)
  }))

test('quote toggles rather than nesting', async () => {
  await withMemoEditor('A line\n', (editor, states) => {
    placeCaret(editor, 2)
    const ctx = ctxOf(editor)
    editor.format('quote')
    expect(serialize(ctx)).toBe('> A line\n')
    expect(states.at(-1)?.quoted).toBe(true)
    expect(states.at(-1)?.block).toEqual({ type: 'paragraph' })
    editor.format('quote')
    expect(serialize(ctx)).toBe('A line\n')
    expect(states.at(-1)?.quoted).toBe(false)
  })
})

test('a list inside a quote reports both', async () => {
  await withMemoEditor('> - item\n', (editor, states) => {
    placeCaret(editor, 4)
    expect(states.at(-1)?.quoted).toBe(true)
    expect(states.at(-1)?.block).toEqual({ type: 'bulletList' })
    editor.format('quote')
    expect(serialize(ctxOf(editor))).toBe('- item\n')
  })
})

test('quote wraps the whole list when the caret is in an item', async () => {
  await withMemoEditor('- one\n- two\n', (editor, states) => {
    placeCaret(editor, 3)
    editor.format('quote')
    expect(serialize(ctxOf(editor))).toBe('> - one\n> - two\n')
    expect(states.at(-1)?.quoted).toBe(true)
    editor.format('quote')
    expect(serialize(ctxOf(editor))).toBe('- one\n- two\n')
  })
})

test('select all then quote toggles once', async () => {
  await withMemoEditor('one\n\ntwo\n', (editor, states) => {
    const view = ctxOf(editor).get(editorViewCtx)
    view.dispatch(view.state.tr.setSelection(new AllSelection(view.state.doc)))
    editor.format('quote')
    expect(serialize(ctxOf(editor))).toBe('> one\n>\n> two\n')
    view.dispatch(view.state.tr.setSelection(new AllSelection(view.state.doc)))
    expect(states.at(-1)?.quoted).toBe(true)
    editor.format('quote')
    expect(serialize(ctxOf(editor))).toBe('one\n\ntwo\n')
  })
})

test('a selection reaching out of a quote is not reported as quoted', async () => {
  await withMemoEditor('> one\n\ntwo\n', (editor, states) => {
    const view = ctxOf(editor).get(editorViewCtx)
    view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, 2, 9)))
    expect(states.at(-1)?.quoted).toBe(false)
  })
})

test('inline code at a caret applies to what is typed next', async () => {
  await withMemoEditor('A line\n', (editor, states) => {
    placeCaret(editor, 3)
    editor.format('code')
    expect(states.at(-1)?.marks).toEqual(['code'])
    const view = ctxOf(editor).get(editorViewCtx)
    view.dispatch(view.state.tr.insertText('xy'))
    expect(serialize(ctxOf(editor))).toBe('A `xy`line\n')
    // The mark is not inclusive, so typing on leaves the code span.
    expect(states.at(-1)?.marks).toEqual([])
    placeCaret(editor, 4)
    expect(states.at(-1)?.marks).toEqual(['code'])
    editor.format('code')
    expect(serialize(ctxOf(editor))).toBe('A xyline\n')
  })
})

test('inline code toggled on and off again at a caret leaves nothing behind', async () => {
  await withMemoEditor('A line\n', (editor, states) => {
    placeCaret(editor, 3)
    editor.format('code')
    editor.format('code')
    expect(states.at(-1)?.marks).toEqual([])
    const view = ctxOf(editor).get(editorViewCtx)
    view.dispatch(view.state.tr.insertText('x'))
    expect(serialize(ctxOf(editor))).toBe('A xline\n')
  })
})

test('canceling a pending code mark leaves the span next to the caret alone', async () => {
  await withMemoEditor('A `foo` b\n', (editor, states) => {
    placeCaret(editor, 6)
    editor.format('code')
    expect(states.at(-1)?.marks).toEqual(['code'])
    editor.format('code')
    expect(states.at(-1)?.marks).toEqual([])
    expect(serialize(ctxOf(editor))).toBe('A `foo` b\n')
  })
})

test('code off inside a span puts the caret back', async () => {
  await withMemoEditor('A `foo` b\n', (editor) => {
    placeCaret(editor, 5)
    editor.format('code')
    expect(serialize(ctxOf(editor))).toBe('A foo b\n')
    const view = ctxOf(editor).get(editorViewCtx)
    expect(view.state.selection.empty).toBe(true)
    expect(view.state.selection.from).toBe(5)
  })
})

test('a list command toggles its own kind and converts the other', async () => {
  await withMemoEditor('- one\n- two\n', (editor, states) => {
    placeCaret(editor, 3)
    expect(states.at(-1)?.block).toEqual({ type: 'bulletList' })
    editor.format('orderedList')
    expect(serialize(ctxOf(editor))).toBe('1. one\n2. two\n')
    expect(states.at(-1)?.block).toEqual({ type: 'orderedList' })
    editor.format('bulletList')
    expect(serialize(ctxOf(editor))).toBe('- one\n- two\n')
    editor.format('bulletList')
    expect(serialize(ctxOf(editor))).toBe('one\n\n- two\n')
    expect(states.at(-1)?.block).toEqual({ type: 'paragraph' })
  })
})

test('backspace at the start of a quote leaves it', async () => {
  await withMemoEditor('> A line\n', (editor) => {
    placeCaret(editor, 2)
    const view = ctxOf(editor).get(editorViewCtx)
    const event = new KeyboardEvent('keydown', { key: 'Backspace', code: 'Backspace' })
    const handled = view.someProp('handleKeyDown', (handler) => handler(view, event))
    expect(handled).toBe(true)
    expect(serialize(ctxOf(editor))).toBe('A line\n')
  })
})

test('backspace at the start of a first list item that holds more lifts the whole item', async () => {
  const cases: [string, number, string][] = [
    ['- A\n  - a1\n- B\n', 3, 'A\n\n- a1\n- B\n'],
    ['Intro\n\n- A\n  - a1\n', 10, 'Intro\n\nA\n\n- a1\n'],
    ['- x\n  - A\n    - a1\n  - B\n', 8, '- x\n\n  A\n  - a1\n  - B\n'],
    ['1. A\n   1. a1\n2. B\n', 3, 'A\n\n1. a1\n2. B\n'],
    ['- [ ] A\n  - [ ] a1\n', 3, 'A\n\n- [ ] a1\n'],
    ['> - A\n>   - a1\n', 4, '> A\n>\n> - a1\n'],
    ['- A\n\n  ```\n  code\n  ```\n', 3, 'A\n\n```\ncode\n```\n'],
    ['- A\n\n  more\n- B\n', 3, 'A\n\nmore\n\n- B\n'],
    ['- A\n  1. a1\n- B\n', 3, 'A\n\n1. a1\n\n- B\n'],
  ]
  for (const [markdown, caret, expected] of cases) {
    await withMemoEditor(markdown, (editor) => {
      placeCaret(editor, caret)
      const view = ctxOf(editor).get(editorViewCtx)
      expect(view.state.selection.$from.parent.textContent).toBe('A')
      const event = new KeyboardEvent('keydown', { key: 'Backspace', code: 'Backspace' })
      expect(view.someProp('handleKeyDown', (handler) => handler(view, event))).toBe(true)
      expect(serialize(ctxOf(editor))).toBe(expected)
      const { $from } = view.state.selection
      expect([$from.parent.textContent, $from.parentOffset]).toEqual(['A', 0])
    })
  }
})

test('a fenced block with a known language is colored, one without stays plain', async () => {
  await withMemoEditor('```js\nconst x = 1\n```\n\n```\nplain\n```\n', (editor) => {
    const view = ctxOf(editor).get(editorViewCtx)
    const spans = view.dom.querySelectorAll('pre [class*="hljs-"]')
    expect(spans.length).toBeGreaterThan(0)
    expect(view.dom.querySelectorAll('pre')[1]?.querySelector('[class*="hljs-"]')).toBeNull()
    expect(serialize(ctxOf(editor))).toBe('```js\nconst x = 1\n```\n\n```\nplain\n```\n')
  })
})

test('control characters typed into the memo are dropped', async () => {
  await withMemoEditor('Plan\n', (editor) => {
    const view = ctxOf(editor).get(editorViewCtx)
    placeCaret(editor, 1)
    const swallowed = view.someProp('handleTextInput', (handler) =>
      handler(view, 1, 1, '\u000e', () => view.state.tr),
    )
    expect(swallowed).toBe(true)
    const typed = view.someProp('handleTextInput', (handler) =>
      handler(view, 1, 1, 'a', () => view.state.tr),
    )
    expect(typed).not.toBe(true)
    expect(serialize(ctxOf(editor))).toBe('Plan\n')
  })
})

test('list items indent with Tab alone, leaving Mod-[ and Mod-] to the app', async () => {
  await withMemoEditor('- one\n- two\n', (editor) => {
    placeCaret(editor, 9)
    const view = ctxOf(editor).get(editorViewCtx)
    const press = (key: string, init: KeyboardEventInit = {}) =>
      view.someProp('handleKeyDown', (f) => f(view, new KeyboardEvent('keydown', { key, ...init })))
    expect(press(']', { metaKey: true })).toBeFalsy()
    expect(press('Tab')).toBe(true)
    expect(serialize(ctxOf(editor))).toBe('- one\n  - two\n')
    expect(press('[', { metaKey: true })).toBeFalsy()
    expect(press('Tab', { shiftKey: true })).toBe(true)
    expect(serialize(ctxOf(editor))).toBe('- one\n- two\n')
  })
})

test('the heading under the caret carries its marks, the others do not', async () => {
  await withMemoEditor('# One\n\nText\n\n## Two\n', (editor) => {
    const view = ctxOf(editor).get(editorViewCtx)
    placeCaret(editor, 2)
    expect(view.dom.querySelector('h1.editing')).not.toBeNull()
    expect(view.dom.querySelector('h2.editing')).toBeNull()
    placeCaret(editor, 9)
    expect(view.dom.querySelector('.editing')).toBeNull()
    expect(serialize(ctxOf(editor))).toBe('# One\n\nText\n\n## Two\n')
  })
  await withMemoEditor('> # Quoted\n', (editor) => {
    placeCaret(editor, 3)
    expect(
      ctxOf(editor).get(editorViewCtx).dom.querySelector('blockquote > h1.editing'),
    ).not.toBeNull()
  })
})

test('an empty memo turned into a heading shows the marks, not the placeholder', async () => {
  await withMemoEditor('', (editor) => {
    const view = ctxOf(editor).get(editorViewCtx)
    expect(view.dom.querySelector('.empty')).not.toBeNull()
    editor.format('heading', 1)
    expect(view.dom.querySelector('h1.editing')).not.toBeNull()
    expect(view.dom.querySelector('.empty')).toBeNull()
  })
})

test('dropped paths become paragraphs after the block, or replace an empty one', async () => {
  await withMemoEditor('- item\n\nText\n', (editor) => {
    placeCaret(editor, 3)
    // A point outside the (unlaid-out) page resolves to the caret.
    editor.insertPaths(['/a/b.txt', '/c d/e_f.pdf'], -100, -100)
    expect(serialize(ctxOf(editor))).toBe('- item\n\n/a/b.txt\n\n/c d/e\\_f.pdf\n\nText\n')
    const view = ctxOf(editor).get(editorViewCtx)
    expect(view.state.selection.$from.parent.textContent).toBe('/c d/e_f.pdf')
  })
  await withMemoEditor('', (editor) => {
    editor.insertPaths(['/only'], -100, -100)
    expect(serialize(ctxOf(editor))).toBe('/only\n')
  })
})

test('formatting keys are the ones the app sets', async () => {
  await withMemoEditor('word\n', (editor) => {
    const view = ctxOf(editor).get(editorViewCtx)
    const press = (key: string, init: KeyboardEventInit = {}) =>
      view.someProp('handleKeyDown', (f) => f(view, new KeyboardEvent('keydown', { key, ...init })))
    view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, 1, 5)))
    // The preset's own Mod-b is gone until the app binds something.
    expect(press('b', { metaKey: true })).toBeFalsy()
    editor.setKeymap({ bold: ['Mod-b'], heading2: ['Mod-Alt-2'], unknown: ['Mod-u'] })
    expect(press('b', { metaKey: true })).toBe(true)
    expect(serialize(ctxOf(editor))).toBe('**word**\n')
    expect(press('2', { metaKey: true, altKey: true })).toBe(true)
    expect(serialize(ctxOf(editor))).toBe('## **word**\n')
    expect(press('u', { metaKey: true })).toBeFalsy()
    editor.setKeymap({ bold: ['Mod-Shift-b'] })
    expect(press('b', { metaKey: true })).toBeFalsy()
  })
})

function paste(editor: MemoEditor, data: Record<string, string>, files: File[] = []): boolean {
  const view = ctxOf(editor).get(editorViewCtx)
  const event = {
    clipboardData: { getData: (type: string) => data[type] ?? '', types: Object.keys(data), files },
  } as unknown as ClipboardEvent
  return view.someProp('handlePaste', (handler) => handler(view, event, Slice.empty)) ?? false
}

test('pasting a url over a selection links what is selected', async () => {
  await withMemoEditor('Read the notes\n', (editor) => {
    const view = ctxOf(editor).get(editorViewCtx)
    view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, 10, 15)))
    expect(paste(editor, { 'text/plain': 'https://example.com' })).toBe(true)
    expect(serialize(ctxOf(editor))).toBe('Read the [notes](https://example.com)\n')
  })
})

test('pasting a url with nothing selected links nothing', async () => {
  await withMemoEditor('A line\n', (editor) => {
    placeCaret(editor, 3)
    paste(editor, { 'text/plain': 'https://example.com' })
    expect(serialize(ctxOf(editor))).not.toContain('](https://example.com)')
  })
})

test('pasting an image asks the app for its bytes', async () => {
  let asked = 0
  await withMemoEditor(
    'A line\n',
    (editor) => {
      const file = new File([new Uint8Array([1])], 'shot.png', { type: 'image/png' })
      expect(paste(editor, { 'text/plain': '' }, [file])).toBe(true)
    },
    () => {
      asked += 1
    },
  )
  expect(asked).toBe(1)
})

test('an image pasted in is written as a reference', async () => {
  await withMemoEditor('\n', (editor) => {
    editor.insertImages([{ path: `images/${'c'.repeat(64)}.png`, alt: 'Shot' }], null, null)
    expect(serialize(ctxOf(editor))).toBe(`![Shot](images/${'c'.repeat(64)}.png)\n`)
  })
})

test('a memo changed under the caret keeps it where it was', async () => {
  await withMemoEditor('One line here\n', (editor) => {
    placeCaret(editor, 5)
    editor.reload('One line here, and more\n', 2)
    const { selection } = ctxOf(editor).get(editorViewCtx).state
    expect(selection.from).toBe(5)
    expect(editor.markdown()).toBe(null)
  })
})

const own = `images/${'a'.repeat(64)}.png`

test("a memo's own image is drawn from the app, at the width in its alt text", async () => {
  await withMemoEditor(`![Dusk|320](${own})\n`, (editor) => {
    const image = ctxOf(editor)
      .get(editorViewCtx)
      .dom.querySelector('.image img') as HTMLImageElement
    expect(image.getAttribute('src')).toBe(`memo-image://memo/${own}`)
    expect(image.alt).toBe('Dusk')
    expect(image.style.width).toBe('320px')
  })
})

test('an image from the web is shown as its alt text, never fetched', async () => {
  await withMemoEditor('![Somewhere else](https://example.com/far.png)\n', (editor) => {
    const dom = ctxOf(editor).get(editorViewCtx).dom
    expect(dom.querySelector('.image img')).toBe(null)
    expect(dom.querySelector('.image-absent')?.textContent).toBe('Somewhere else')
  })
})

test('dragging the handle writes the new width into the memo', async () => {
  await withMemoEditor(`![Dusk|320](${own})\n`, (editor) => {
    const dom = ctxOf(editor).get(editorViewCtx).dom
    const handle = dom.querySelector('.image-handle') as HTMLElement
    const image = dom.querySelector('.image img') as HTMLImageElement
    image.getBoundingClientRect = () => ({ width: 320 }) as DOMRect
    Object.defineProperty(dom, 'clientWidth', { value: 600, configurable: true })
    handle.dispatchEvent(new PointerEvent('pointerdown', { clientX: 0, bubbles: true }))
    handle.dispatchEvent(new PointerEvent('pointermove', { clientX: 60, bubbles: true }))
    handle.dispatchEvent(new PointerEvent('pointerup', { clientX: 60, bubbles: true }))
    expect(serialize(ctxOf(editor))).toBe(`![Dusk|380](${own})\n`)
  })
})

test('a picture sized wider than the memo is held to it', async () => {
  await withMemoEditor(`![Dusk|320](${own})\n`, (editor) => {
    const dom = ctxOf(editor).get(editorViewCtx).dom
    const handle = dom.querySelector('.image-handle') as HTMLElement
    const image = dom.querySelector('.image img') as HTMLImageElement
    image.getBoundingClientRect = () => ({ width: 320 }) as DOMRect
    Object.defineProperty(dom, 'clientWidth', { value: 400, configurable: true })
    handle.dispatchEvent(new PointerEvent('pointerdown', { clientX: 0, bubbles: true }))
    handle.dispatchEvent(new PointerEvent('pointermove', { clientX: 900, bubbles: true }))
    handle.dispatchEvent(new PointerEvent('pointerup', { clientX: 900, bubbles: true }))
    expect(serialize(ctxOf(editor))).toBe(`![Dusk|400](${own})\n`)
  })
})

test('clearing find collapses the selection without editing text or undo history', async () =>
  withMemoEditor('A searchable line.\n', (editor) => {
    const view = ctxOf(editor).get(editorViewCtx)
    editor.find('searchable')
    expect(getMatchHighlights(view.state).find().length).toBe(1)
    editor.find('')
    expect(getMatchHighlights(view.state).find()).toHaveLength(0)
    expect(view.state.selection.empty).toBe(true)
    expect(view.state.selection.from).toBe(13)
    expect(editor.markdown()).toBeNull()
  }))

test('find matches styled text, advances, wraps and clears a missing query', async () =>
  withMemoEditor('A **searchable** line. Another searchable line.\n', (editor) => {
    const view = ctxOf(editor).get(editorViewCtx)
    editor.find('SEARCHABLE')
    const first = view.state.selection.from
    expect(view.state.doc.textBetween(view.state.selection.from, view.state.selection.to)).toBe(
      'searchable',
    )
    expect(getMatchHighlights(view.state).find()).toHaveLength(2)
    editor.find('SEARCHABLE')
    expect(view.state.selection.from).toBeGreaterThan(first)
    editor.find('SEARCHABLE')
    expect(view.state.selection.from).toBe(first)
    editor.find('missing')
    expect(getMatchHighlights(view.state).find()).toHaveLength(0)
    expect(view.state.selection.empty).toBe(true)
    expect(editor.markdown()).toBeNull()
  }))

test('loading another memo clears previous search highlights', async () =>
  withMemoEditor('A line.\n', (editor) => {
    editor.find('line')
    editor.load('Another line.\n', 2)
    expect(getMatchHighlights(ctxOf(editor).get(editorViewCtx).state).find()).toHaveLength(0)
  }))
