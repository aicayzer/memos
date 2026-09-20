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
  blockquoteSchema,
  createCodeBlockCommand,
  inlineCodeSchema,
  linkSchema,
  toggleEmphasisCommand,
  toggleInlineCodeCommand,
  toggleLinkCommand,
  toggleStrongCommand,
  turnIntoTextCommand,
  wrapInBulletListCommand,
  wrapInHeadingCommand,
  wrapInOrderedListCommand,
} from '@milkdown/kit/preset/commonmark'
import { toggleStrikethroughCommand } from '@milkdown/kit/preset/gfm'
import {
  NodeRange,
  type MarkType,
  type Node as ProseNode,
  type ResolvedPos,
} from '@milkdown/kit/prose/model'
import { findWrapping, liftTarget } from '@milkdown/kit/prose/transform'
import {
  AllSelection,
  Plugin,
  PluginKey,
  Selection,
  TextSelection,
  type EditorState,
} from '@milkdown/kit/prose/state'
import { $prose, callCommand, replaceAll } from '@milkdown/kit/utils'
import { dialect, serialize, stringifyOptions } from './dialect'
import { taskListPlugin, toggleTaskList } from './tasks'

export type Mark = 'bold' | 'italic' | 'strikethrough' | 'code' | 'link'

export type Block =
  | { type: 'paragraph' }
  | { type: 'heading'; level: number }
  | { type: 'codeBlock' }
  | { type: 'bulletList' }
  | { type: 'orderedList' }
  | { type: 'taskList' }

export interface CaretState {
  marks: Mark[]
  block: Block
  /** Inside a blockquote at any depth; the block is what sits inside it. */
  quoted: boolean
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
  changed(markdown: string, generation: number): void
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

// Select All resolves at the document level, where no block can be read.
function textBounds(state: EditorState): { $from: ResolvedPos; $to: ResolvedPos } {
  const { selection, doc } = state
  if (selection instanceof AllSelection)
    return TextSelection.between(doc.resolve(0), doc.resolve(doc.content.size))
  return selection
}

function caretState(state: EditorState): CaretState {
  const { empty } = state.selection
  const { $from, $to } = textBounds(state)
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
  return { marks: [...active], block: blockAt($from.parent, $from), quoted: quoted($from, $to) }
}

// True only when one quote holds the whole selection, so the state matches what the command can lift.
function quoted($from: ResolvedPos, $to: ResolvedPos): boolean {
  return $from.blockRange($to, (node) => node.type.name === 'blockquote') != null
}

function blockAt(parent: ProseNode, $from: EditorState['selection']['$from']): Block {
  for (let depth = $from.depth; depth > 0; depth--) {
    const node = $from.node(depth)
    switch (node.type.name) {
      case 'heading':
        return { type: 'heading', level: node.attrs.level }
      case 'code_block':
        return { type: 'codeBlock' }
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

// The listener plugin reports selection changes from inside state.apply, before
// the view holds the new state, so the caret state is read from the view instead.
function caretStatePlugin(events: EditorEvents) {
  return $prose(
    () =>
      new Plugin({
        key: new PluginKey('caretState'),
        view: () => ({
          update(view, previous) {
            const { state } = view
            if (
              state.selection.eq(previous.selection) &&
              state.doc.eq(previous.doc) &&
              state.storedMarks === previous.storedMarks
            )
              return
            events.stateChanged(caretState(state))
          },
        }),
      }),
  )
}

function outermostListDepth($pos: ResolvedPos): number | null {
  for (let depth = 1; depth <= $pos.depth; depth++) {
    const name = $pos.node(depth).type.name
    if (name === 'bullet_list' || name === 'ordered_list') return depth
  }
  return null
}

export class MemoEditor {
  private editor!: Editor
  private lastMarkdown = ''
  private baseline = ''
  private generation = 0

  private constructor(private readonly events: EditorEvents) {}

  static async mount(root: HTMLElement, events: EditorEvents): Promise<MemoEditor> {
    const instance = new MemoEditor(events)
    instance.editor = await Editor.make()
      .config((ctx) => {
        ctx.set(rootCtx, root)
        ctx.set(defaultValueCtx, '')
        ctx.set(remarkStringifyOptionsCtx, stringifyOptions)
        ctx.get(listenerCtx).updated((ctx, doc) => {
          const markdown = serialize(ctx, doc)
          if (markdown === instance.lastMarkdown) return
          instance.lastMarkdown = markdown
          events.changed(markdown, instance.generation)
        })
      })
      .use(caretStatePlugin(events))
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

  load(markdown: string, generation: number): void {
    // A loaded document only counts as changed once it is edited, so its
    // canonical form is the baseline, not the text as stored.
    this.generation = generation
    this.editor.action(replaceAll(markdown, true))
    this.baseline = serialize(this.editor.ctx)
    this.lastMarkdown = this.baseline
    const view = this.editor.ctx.get(editorViewCtx)
    view.dispatch(view.state.tr.setSelection(Selection.atStart(view.state.doc)))
    this.events.stateChanged(caretState(view.state))
  }

  /** The document as markdown, or null while it is still what was loaded. */
  markdown(): string | null {
    const markdown = serialize(this.editor.ctx)
    return markdown === this.baseline ? null : markdown
  }

  focus(): void {
    this.editor.ctx.get(editorViewCtx).focus()
  }

  // Removing a mark at a caret only clears the stored mark, so the whole
  // marked run is selected first. Returns false when the caret is not in one.
  private selectMarkAtCaret(mark: MarkType): boolean {
    const view = this.editor.ctx.get(editorViewCtx)
    const { selection, doc } = view.state
    if (!selection.empty) return false
    const $pos = selection.$from
    const parent = $pos.parent
    const start = $pos.start()
    let from = $pos.pos
    let to = $pos.pos
    parent.forEach((child, offset) => {
      const childFrom = start + offset
      const childTo = childFrom + child.nodeSize
      if (!mark.isInSet(child.marks)) return
      if (childTo >= $pos.pos && childFrom <= to) {
        from = Math.min(from, childFrom)
        to = Math.max(to, childTo)
      }
    })
    if (from === to) return false
    view.dispatch(view.state.tr.setSelection(TextSelection.create(doc, from, to)))
    return true
  }

  // Milkdown's inline code command ignores a caret; a stored mark makes the
  // next typed text code, the way bold and italic behave.
  private toggleInlineCode(): void {
    const view = this.editor.ctx.get(editorViewCtx)
    const type = inlineCodeSchema.type(this.editor.ctx)
    const run = () => {
      this.editor.action(callCommand(toggleInlineCodeCommand.key))
    }
    if (!view.state.selection.empty) return run()
    const active = type.isInSet(view.state.storedMarks ?? view.state.selection.$from.marks())
    if (!active) view.dispatch(view.state.tr.addStoredMark(type.create()))
    else if (this.selectMarkAtCaret(type)) run()
    else view.dispatch(view.state.tr.removeStoredMark(type))
  }

  private quote(): void {
    const view = this.editor.ctx.get(editorViewCtx)
    const type = blockquoteSchema.type(this.editor.ctx)
    const { $from, $to } = textBounds(view.state)
    let range = $from.blockRange($to)
    let wrapping = range && findWrapping(range, type)
    if (!wrapping) {
      // A list item cannot hold a quote, so the whole list is quoted instead.
      const depth = outermostListDepth($from)
      if (depth == null) return
      const doc = view.state.doc
      range = new NodeRange(
        doc.resolve($from.before(depth)),
        doc.resolve($from.after(depth)),
        depth - 1,
      )
      wrapping = findWrapping(range, type)
    }
    if (!range || !wrapping) return
    view.dispatch(view.state.tr.wrap(range, wrapping))
  }

  private unquote(): void {
    const view = this.editor.ctx.get(editorViewCtx)
    const { $from, $to } = textBounds(view.state)
    const range = $from.blockRange($to, (node) => node.type.name === 'blockquote')
    if (!range) return
    const target = liftTarget(range)
    if (target == null) return
    view.dispatch(view.state.tr.lift(range, target))
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
        this.toggleInlineCode()
        break
      case 'codeBlock':
        if (state.block.type === 'codeBlock') run(turnIntoTextCommand.key)
        else run(createCodeBlockCommand.key, typeof arg === 'string' ? arg : '')
        break
      case 'quote':
        if (state.quoted) this.unquote()
        else this.quote()
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
        if (state.marks.includes('link')) this.selectMarkAtCaret(linkSchema.type(this.editor.ctx))
        run(toggleLinkCommand.key, typeof arg === 'string' ? { href: arg } : {})
        break
    }
    this.focus()
  }
}
