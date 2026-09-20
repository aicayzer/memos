import type { RootContent } from 'hast'
import { common, createLowlight } from 'lowlight'
import type { Node as ProseNode } from '@milkdown/kit/prose/model'
import { Plugin, PluginKey } from '@milkdown/kit/prose/state'
import { Decoration, DecorationSet } from '@milkdown/kit/prose/view'
import { $prose } from '@milkdown/kit/utils'

const lowlight = createLowlight(common)

// Colors are decorations over the plain text, so the markdown is untouched;
// a block without a known language stays plain.
function decorations(doc: ProseNode): DecorationSet {
  const found: Decoration[] = []
  doc.descendants((node, pos) => {
    if (node.type.name !== 'code_block') return true
    const language = String(node.attrs.language ?? '').toLowerCase()
    if (!language || !lowlight.registered(language)) return false
    let offset = pos + 1
    const walk = (children: RootContent[], classes: string[]) => {
      for (const child of children) {
        if (child.type === 'text') {
          const end = offset + child.value.length
          if (classes.length > 0)
            found.push(Decoration.inline(offset, end, { class: classes.join(' ') }))
          offset = end
        } else if (child.type === 'element') {
          const own = (child.properties?.className as string[] | undefined) ?? []
          walk(child.children, [...classes, ...own])
        }
      }
    }
    walk(lowlight.highlight(language, node.textContent).children, [])
    return false
  })
  return DecorationSet.create(doc, found)
}

export const highlightPlugin = $prose(
  () =>
    new Plugin<DecorationSet>({
      key: new PluginKey('highlight'),
      state: {
        init: (_, state) => decorations(state.doc),
        apply: (tr, previous) =>
          tr.docChanged ? decorations(tr.doc) : previous.map(tr.mapping, tr.doc),
      },
      props: {
        decorations(state) {
          return this.getState(state)
        },
      },
    }),
)
