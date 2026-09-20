import { expect, test } from 'vitest'
import { editorViewCtx } from '@milkdown/kit/core'
import type { Ctx } from '@milkdown/kit/ctx'
import { AllSelection, TextSelection } from '@milkdown/kit/prose/state'
import { serialize } from '../src/dialect'
import { MemoEditor, type CaretState } from '../src/editor'

async function withMemoEditor<T>(
  markdown: string,
  run: (editor: MemoEditor, states: CaretState[]) => T,
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
