import { Editor, defaultValueCtx, remarkStringifyOptionsCtx, rootCtx } from '@milkdown/kit/core'
import { getMarkdown } from '@milkdown/kit/utils'
import { dialect, stringifyOptions } from '../src/dialect'

export async function roundTrip(markdown: string): Promise<string> {
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
  const out = editor.action(getMarkdown())
  await editor.destroy()
  root.remove()
  return out
}
