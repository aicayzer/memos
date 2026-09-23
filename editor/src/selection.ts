import { Plugin, PluginKey, type EditorState } from '@milkdown/kit/prose/state'
import { Decoration, DecorationSet, type EditorView } from '@milkdown/kit/prose/view'
import { $prose } from '@milkdown/kit/utils'

/** The stylesheet paints the selection under this name. */
const name = 'selection'

interface Span {
  from: number
  to: number
}

/** The text a selection covers, run by run within each block, and the images among it. */
function covered(state: EditorState): { text: Span[]; images: Span[] } | null {
  const { from, to, empty, visible } = state.selection
  if (empty || !visible) return null
  const text: Span[] = []
  const images: Span[] = []
  state.doc.nodesBetween(from, to, (node, pos) => {
    if (!node.isTextblock) return true
    let start = Math.max(from, pos + 1)
    const end = Math.min(to, pos + node.nodeSize - 1)
    node.forEach((child, offset) => {
      const at = pos + 1 + offset
      if (child.type.name !== 'image' || at < start || at + child.nodeSize > end) return
      if (at > start) text.push({ from: start, to: at })
      images.push({ from: at, to: at + child.nodeSize })
      start = at + child.nodeSize
    })
    if (end > start) text.push({ from: start, to: end })
    return false
  })
  return { text, images }
}

function domRange(view: EditorView, span: Span): Range {
  const start = view.domAtPos(span.from)
  const end = view.domAtPos(span.to)
  const range = document.createRange()
  range.setStart(start.node, start.offset)
  range.setEnd(end.node, end.offset)
  return range
}

// A range that so much as reaches the block an image sits in has WebKit paint a square box over the
// image, past its rounded corners, so the highlight is laid over the runs of text alone.
function paint(view: EditorView, highlight: Highlight): void {
  highlight.clear()
  for (const span of covered(view.state)?.text ?? []) highlight.add(domRange(view, span))
}

// WebKit paints a selection across blocks into the margins beside and between its lines, one wide
// box. The engine's own selection is left unpainted and the text it covers is drawn through a
// highlight, which paints text alone. An image is tinted through a decoration instead; a node
// selection keeps the outline it already had.
export const selectionPlugin = $prose(
  () =>
    new Plugin({
      key: new PluginKey('selection'),
      view(view) {
        const highlight = new Highlight()
        CSS.highlights.set(name, highlight)
        paint(view, highlight)
        return {
          update: (view) => paint(view, highlight),
          destroy: () => CSS.highlights.delete(name),
        }
      },
      props: {
        decorations(state) {
          const selection = covered(state)
          if (!selection) return null
          return DecorationSet.create(
            state.doc,
            selection.images.map((image) =>
              Decoration.node(image.from, image.to, { class: 'in-selection' }),
            ),
          )
        },
      },
    }),
)
