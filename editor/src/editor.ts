import {
  Editor,
  defaultValueCtx,
  editorViewCtx,
  remarkStringifyOptionsCtx,
  rootCtx,
} from '@milkdown/kit/core'
import { clipboard } from '@milkdown/kit/plugin/clipboard'
import { history } from '@milkdown/kit/plugin/history'
import { listener, listenerCtx } from '@milkdown/kit/plugin/listener'
import { cursor } from '@milkdown/kit/plugin/cursor'
import {
  createCodeBlockCommand,
  toggleEmphasisCommand,
  toggleInlineCodeCommand,
  toggleLinkCommand,
  toggleStrongCommand,
  turnIntoTextCommand,
  wrapInBlockquoteCommand,
  wrapInBulletListCommand,
  wrapInHeadingCommand,
  wrapInOrderedListCommand,
} from '@milkdown/kit/preset/commonmark'
import { toggleStrikethroughCommand } from '@milkdown/kit/preset/gfm'
import type { Node as ProseNode } from '@milkdown/kit/prose/model'
import { Selection, type EditorState } from '@milkdown/kit/prose/state'
import { callCommand, replaceAll } from '@milkdown/kit/utils'
import { dialect, serialize, stringifyOptions } from './dialect'
import { taskListPlugin, toggleTaskList } from './tasks'

export type Mark = 'bold' | 'italic' | 'strikethrough' | 'code' | 'link'

export type Block =
  | { type: 'paragraph' }
  | { type: 'heading'; level: number }
  | { type: 'codeBlock' }
  | { type: 'quote' }
  | { type: 'bulletList' }
  | { type: 'orderedList' }
  | { type: 'taskList' }

export interface CaretState {
  marks: Mark[]
  block: Block
}

export type FormatCommand =
  | 'heading'
  | 'paragraph'
  | 'bold'
  | 'italic'
  | 'strikethrough'
  | 'code'
  | 'codeBlock'
  | 'quote'
  | 'bulletList'
  | 'orderedList'
  | 'taskList'
  | 'link'

export interface EditorEvents {
  changed(markdown: string): void
  stateChanged(state: CaretState): void
  openLink(href: string): void
}

const markNames: Record<string, Mark> = {
  strong: 'bold',
  emphasis: 'italic',
  strike_through: 'strikethrough',
  inlineCode: 'code',
  link: 'link',
}

function caretState(state: EditorState): CaretState {
  const { $from, $to, empty } = state.selection
  const active = new Set<Mark>()
  const marks = empty ? (state.storedMarks ?? $from.marks()) : []
  for (const mark of marks) {
    const name = markNames[mark.type.name]
    if (name) active.add(name)
  }
  if (!empty) {
    for (const [name, mark] of Object.entries(markNames)) {
      const type = state.schema.marks[name]
      if (type && state.doc.rangeHasMark($from.pos, $to.pos, type)) active.add(mark)
    }
  }
  return { marks: [...active], block: blockAt($from.parent, $from) }
}

function blockAt(parent: ProseNode, $from: EditorState['selection']['$from']): Block {
  for (let depth = $from.depth; depth > 0; depth--) {
    const node = $from.node(depth)
    switch (node.type.name) {
      case 'heading':
        return { type: 'heading', level: node.attrs.level }
      case 'code_block':
        return { type: 'codeBlock' }
      case 'blockquote':
        return { type: 'quote' }
      case 'list_item':
        return node.attrs.checked == null
          ? {
              type:
                $from.node(depth - 1).type.name === 'ordered_list' ? 'orderedList' : 'bulletList',
            }
          : { type: 'taskList' }
    }
  }
  if (parent.type.name === 'heading') return { type: 'heading', level: parent.attrs.level }
  return { type: 'paragraph' }
}

export class MemoEditor {
  private editor!: Editor
  private lastMarkdown = ''
  private loading = false

  private constructor(private readonly events: EditorEvents) {}

  static async mount(root: HTMLElement, events: EditorEvents): Promise<MemoEditor> {
    const instance = new MemoEditor(events)
    instance.editor = await Editor.make()
      .config((ctx) => {
        ctx.set(rootCtx, root)
        ctx.set(defaultValueCtx, '')
        ctx.set(remarkStringifyOptionsCtx, stringifyOptions)
        const listeners = ctx.get(listenerCtx)
        listeners.updated((ctx, doc) => {
          events.stateChanged(caretState(ctx.get(editorViewCtx).state))
          if (instance.loading) return
          const markdown = serialize(ctx, doc)
          if (markdown === instance.lastMarkdown) return
          instance.lastMarkdown = markdown
          events.changed(markdown)
        })
        listeners.selectionUpdated((ctx) =>
          events.stateChanged(caretState(ctx.get(editorViewCtx).state)),
        )
      })
      .use(dialect)
      .use(listener)
      .use(history)
      .use(clipboard)
      .use(cursor)
      .use(taskListPlugin)
      .create()
    root.addEventListener('click', (event) => {
      const anchor = (event.target as HTMLElement).closest('a[href]')
      if (anchor && event.metaKey) {
        event.preventDefault()
        events.openLink(anchor.getAttribute('href') ?? '')
      }
    })
    return instance
  }

  load(markdown: string): void {
    // A loaded document only counts as changed once it is edited, so its
    // canonical form is the baseline, not the text as stored.
    this.loading = true
    this.editor.action(replaceAll(markdown, true))
    this.loading = false
    this.lastMarkdown = serialize(this.editor.ctx)
    const view = this.editor.ctx.get(editorViewCtx)
    view.dispatch(view.state.tr.setSelection(Selection.atStart(view.state.doc)))
    this.events.stateChanged(caretState(view.state))
  }

  markdown(): string {
    return serialize(this.editor.ctx)
  }

  focus(): void {
    this.editor.ctx.get(editorViewCtx).focus()
  }

  format(command: FormatCommand, arg?: string | number): void {
    const run = (cmd: Parameters<typeof callCommand>[0], payload?: unknown) =>
      this.editor.action(callCommand(cmd, payload))
    const state = caretState(this.editor.ctx.get(editorViewCtx).state)
    switch (command) {
      case 'heading': {
        const level = Number(arg ?? 1)
        if (state.block.type === 'heading' && state.block.level === level)
          run(turnIntoTextCommand.key)
        else run(wrapInHeadingCommand.key, level)
        break
      }
      case 'paragraph':
        run(turnIntoTextCommand.key)
        break
      case 'bold':
        run(toggleStrongCommand.key)
        break
      case 'italic':
        run(toggleEmphasisCommand.key)
        break
      case 'strikethrough':
        run(toggleStrikethroughCommand.key)
        break
      case 'code':
        run(toggleInlineCodeCommand.key)
        break
      case 'codeBlock':
        if (state.block.type === 'codeBlock') run(turnIntoTextCommand.key)
        else run(createCodeBlockCommand.key, typeof arg === 'string' ? arg : '')
        break
      case 'quote':
        run(wrapInBlockquoteCommand.key)
        break
      case 'bulletList':
        run(wrapInBulletListCommand.key)
        break
      case 'orderedList':
        run(wrapInOrderedListCommand.key)
        break
      case 'taskList':
        toggleTaskList(this.editor.ctx)
        break
      case 'link':
        run(toggleLinkCommand.key, typeof arg === 'string' ? { href: arg } : {})
        break
    }
    this.focus()
  }
}
