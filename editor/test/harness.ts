import { Editor, defaultValueCtx, remarkStringifyOptionsCtx, rootCtx } from '@milkdown/kit/core'
import { getMarkdown } from '@milkdown/kit/utils'
import { dialect, stringifyOptions } from '../src/dialect'

export async function withEditor<T>(markdown: string, run: (editor: Editor) => T): Promise<T> {
  const root = document.createElement('div')
  document.body.append(root)
  const editor = await Editor.make()
    .config((ctx) => {
      ctx.set(rootCtx, root)
      ctx.set(defaultValueCtx, markdown)
      ctx.set(remarkStringifyOptionsCtx, stringifyOptions)
    })
    .use(dialect)
    .create()
  try {
    return run(editor)
  } finally {
    await editor.destroy()
    root.remove()
  }
}

export function roundTrip(markdown: string): Promise<string> {
  return withEditor(markdown, (editor) => editor.action(getMarkdown()))
}
