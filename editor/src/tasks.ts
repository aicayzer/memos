import { commandsCtx, editorViewCtx } from '@milkdown/kit/core'
import type { Ctx } from '@milkdown/kit/ctx'
import { wrapInBulletListCommand } from '@milkdown/kit/preset/commonmark'
import type { Node as ProseNode } from '@milkdown/kit/prose/model'
import { Plugin, PluginKey } from '@milkdown/kit/prose/state'
import type { EditorView } from '@milkdown/kit/prose/view'
import { $prose } from '@milkdown/kit/utils'

// A click on the task marker lands on the <li> itself, since the marker is a
// pseudo-element; clicks inside the item's text land on its children.
export const taskListPlugin = $prose(
  () =>
    new Plugin({
      key: new PluginKey('taskToggle'),
      props: {
        handleClickOn(view, _pos, node, nodePos, event) {
          if (node.type.name !== 'list_item' || node.attrs.checked == null) return false
          const target = event.target as HTMLElement
          if (!target.matches('li[data-item-type="task"]')) return false
          view.dispatch(
            view.state.tr.setNodeMarkup(nodePos, undefined, {
              ...node.attrs,
              checked: !node.attrs.checked,
            }),
          )
          return true
        },
      },
    }),
)

function listItemsInSelection(view: EditorView): Array<{ pos: number; node: ProseNode }> {
  const { from, to } = view.state.selection
  const items: Array<{ pos: number; node: ProseNode }> = []
  view.state.doc.nodesBetween(from, to, (node, pos) => {
    if (node.type.name === 'list_item') items.push({ pos, node })
  })
  return items
}

export function toggleTaskList(ctx: Ctx): void {
  const view = ctx.get(editorViewCtx)
  let items = listItemsInSelection(view)
  if (items.length === 0) {
    ctx.get(commandsCtx).call(wrapInBulletListCommand.key)
    items = listItemsInSelection(view)
  }
  const allTasks = items.every(({ node }) => node.attrs.checked != null)
  let tr = view.state.tr
  for (const { pos, node } of items) {
    tr = tr.setNodeMarkup(pos, undefined, {
      ...node.attrs,
      checked: allTasks ? null : (node.attrs.checked ?? false),
    })
  }
  view.dispatch(tr)
}
