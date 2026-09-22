import { linkSchema } from '@milkdown/kit/preset/commonmark'
import { Plugin, PluginKey } from '@milkdown/kit/prose/state'
import { $prose } from '@milkdown/kit/utils'

const url = /^https?:\/\/\S+$/

function carriesImage(data: DataTransfer): boolean {
  if ([...data.files].some((file) => file.type.startsWith('image/'))) return true
  return [...data.types].some((type) => type.startsWith('image/'))
}

/** Two pastes the editor handles itself: an image, whose bytes the app takes off the pasteboard, and a
 *  URL over a selection, which links what is selected rather than replacing it. */
export function pastePlugin(pasteImage: () => void) {
  return $prose(
    (ctx) =>
      new Plugin({
        key: new PluginKey('paste'),
        props: {
          handlePaste: (view, event) => {
            const data = event.clipboardData
            if (!data) return false
            if (carriesImage(data)) {
              pasteImage()
              return true
            }
            const text = data.getData('text/plain').trim()
            const { selection } = view.state
            if (selection.empty || !url.test(text)) return false
            const mark = linkSchema.type(ctx).create({ href: text, title: '' })
            view.dispatch(
              view.state.tr.addMark(selection.from, selection.to, mark).removeStoredMark(mark),
            )
            return true
          },
        },
      }),
  )
}
