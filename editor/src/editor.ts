import {
  Editor,
  defaultValueCtx,
  editorViewCtx,
  editorViewOptionsCtx,
  remarkStringifyOptionsCtx,
  rootCtx,
} from '@milkdown/kit/core'
import { clipboard } from '@milkdown/kit/plugin/clipboard'
import { history } from '@milkdown/kit/plugin/history'
import { listener, listenerCtx } from '@milkdown/kit/plugin/listener'
import { cursor } from '@milkdown/kit/plugin/cursor'
import {
  blockquoteKeymap,
  blockquoteSchema,
  bulletListKeymap,
  codeBlockKeymap,
  createCodeBlockCommand,
  emphasisKeymap,
  headingKeymap,
  inlineCodeKeymap,
  inlineCodeSchema,
  liftListItemCommand,
  linkSchema,
  listItemKeymap,
  orderedListKeymap,
  paragraphKeymap,
  strongKeymap,
  toggleEmphasisCommand,
  toggleInlineCodeCommand,
  toggleLinkCommand,
  toggleStrongCommand,
  turnIntoTextCommand,
  wrapInBulletListCommand,
  wrapInHeadingCommand,
  wrapInOrderedListCommand,
} from '@milkdown/kit/preset/commonmark'
import { strikethroughKeymap, toggleStrikethroughCommand } from '@milkdown/kit/preset/gfm'
import {
  NodeRange,
  type MarkType,
  type Node as ProseNode,
  type ResolvedPos,
} from '@milkdown/kit/prose/model'
import { keydownHandler, keymap } from '@milkdown/kit/prose/keymap'
import type { EditorView } from '@milkdown/kit/prose/view'
import { findWrapping, liftTarget } from '@milkdown/kit/prose/transform'
import {
  AllSelection,
  Plugin,
  PluginKey,
  Selection,
  TextSelection,
  type Command,
  type EditorState,
} from '@milkdown/kit/prose/state'
import { $prose, callCommand, replaceAll, type $UserKeymap } from '@milkdown/kit/utils'
import { codeCopyPlugin, headingMarkPlugin, placeholderPlugin } from './decorations'
import { dialect, serialize, stringifyOptions } from './dialect'
import { highlightPlugin } from './highlight'
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
  /** One quote holds the whole selection; the block is what sits inside it. */
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

/** The bindings the app sets, by shortcut name; each runs a format command. */
export type Keymap = Record<string, string[]>

const shortcutCommands: Record<string, [FormatCommand, number?]> = {
  heading1: ['heading', 1],
  heading2: ['heading', 2],
  heading3: ['heading', 3],
  paragraph: ['paragraph'],
  bold: ['bold'],
  italic: ['italic'],
  strikethrough: ['strikethrough'],
  code: ['code'],
  codeBlock: ['codeBlock'],
  quote: ['quote'],
  bulletList: ['bulletList'],
  orderedList: ['orderedList'],
  taskList: ['taskList'],
}

export interface EditorEvents {
  changed(markdown: string, generation: number): void
  stateChanged(state: CaretState): void
  openLink(href: string): void
  copy(text: string): void
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

// Backspace at the start of a quote's first block is left alone by the preset;
// leaving the quote is what a Backspace there means.
const quoteBackspace = $prose(() =>
  keymap({
    Backspace: (state, dispatch) => {
      const { $from, empty } = state.selection
      if (!empty || $from.parentOffset > 0 || $from.depth < 2) return false
      if (
        $from.node($from.depth - 1).type.name !== 'blockquote' ||
        $from.index($from.depth - 1) > 0
      )
        return false
      const range = $from.blockRange($from, (node) => node.type.name === 'blockquote')
      const target = range && liftTarget(range)
      if (!range || target == null) return false
      dispatch?.(state.tr.lift(range, target).scrollIntoView())
      return true
    },
  }),
)

// A control chord that nothing handles reaches the page as its ASCII control character
// (Control-N as U+000E), which the web view would insert as text.
const controlCharacters = /^[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]+$/
const dropControlCharacters = $prose(
  () =>
    new Plugin({
      key: new PluginKey('dropControlCharacters'),
      props: {
        handleTextInput: (_view, _from, _to, text) => controlCharacters.test(text),
      },
    }),
)

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
    if (isList($pos.node(depth))) return depth
  }
  return null
}

function innermostListDepth($pos: ResolvedPos): number | null {
  for (let depth = $pos.depth; depth >= 1; depth--) {
    if (isList($pos.node(depth))) return depth
  }
  return null
}

function isList(node: ProseNode): boolean {
  return node.type.name === 'bullet_list' || node.type.name === 'ordered_list'
}

export class MemoEditor {
  private editor!: Editor
  private lastMarkdown = ''
  private baseline = ''
  private generation = 0
  private keys: (view: EditorView, event: KeyboardEvent) => boolean = () => false

  private constructor(private readonly events: EditorEvents) {}

  // The app's bindings, replaced whole whenever they change; the plugin stays.
  private keymapPlugin = $prose(
    () =>
      new Plugin({
        key: new PluginKey('appKeymap'),
        props: { handleKeyDown: (view, event) => this.keys(view, event) },
      }),
  )

  static async mount(root: HTMLElement, events: EditorEvents): Promise<MemoEditor> {
    const instance = new MemoEditor(events)
    instance.editor = await Editor.make()
      .config((ctx) => {
        ctx.set(rootCtx, root)
        ctx.set(defaultValueCtx, '')
        ctx.set(remarkStringifyOptionsCtx, stringifyOptions)
        // The preset also binds Mod-[ and Mod-] here; the app uses those for back and forward.
        ctx.update(listItemKeymap.key, (keys) => ({
          ...keys,
          SinkListItem: { shortcuts: 'Tab' },
          LiftListItem: { shortcuts: 'Shift-Tab' },
        }))
        // Formatting keys are the app's to set, through setKeymap; the presets' own go.
        const unbind = <K extends string>(keymap: $UserKeymap<string, K>, keep: K[] = []) =>
          ctx.update(keymap.key, (keys) => {
            const cleared = { ...keys }
            for (const name of Object.keys(cleared) as K[]) {
              if (!keep.includes(name)) cleared[name] = { shortcuts: [] }
            }
            return cleared
          })
        unbind(strongKeymap)
        unbind(emphasisKeymap)
        unbind(inlineCodeKeymap)
        unbind(strikethroughKeymap)
        unbind(headingKeymap, ['DowngradeHeading'])
        unbind(paragraphKeymap)
        unbind(blockquoteKeymap)
        unbind(codeBlockKeymap)
        unbind(bulletListKeymap)
        unbind(orderedListKeymap)
        // The caret is kept above the fade under the formatting bar.
        ctx.update(editorViewOptionsCtx, (options) => ({
          ...options,
          scrollThreshold: { top: 8, right: 0, bottom: 112, left: 0 },
          scrollMargin: { top: 8, right: 0, bottom: 112, left: 0 },
        }))
        ctx.get(listenerCtx).updated((ctx, doc) => {
          const markdown = serialize(ctx, doc)
          if (markdown === instance.lastMarkdown) return
          instance.lastMarkdown = markdown
          events.changed(markdown, instance.generation)
        })
      })
      .use(caretStatePlugin(events))
      .use(instance.keymapPlugin)
      .use(dialect)
      .use(listener)
      .use(history)
      .use(clipboard)
      .use(cursor)
      .use(taskListPlugin)
      .use(quoteBackspace)
      .use(dropControlCharacters)
      .use(codeCopyPlugin((text) => events.copy(text)))
      .use(placeholderPlugin)
      .use(headingMarkPlugin)
      .use(highlightPlugin)
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
    // At the end, where writing carries on; the caret in a first-line heading would show its marks instead.
    view.dispatch(view.state.tr.setSelection(Selection.atEnd(view.state.doc)).scrollIntoView())
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

  /** Binds keys, in ProseMirror's names, to the formatting each shortcut runs. Walked in the table's
   *  order, so a key given to two shortcuts lands the same way every time. */
  setKeymap(keymap: Keymap): void {
    const bindings: Record<string, Command> = {}
    for (const [name, command] of Object.entries(shortcutCommands)) {
      for (const key of keymap[name] ?? []) {
        bindings[key] = () => {
          this.format(...command)
          return true
        }
      }
    }
    this.keys = keydownHandler(bindings)
  }

  /** Dropped files land as one paragraph per path at the drop point: in place of an empty block, after
   *  the top-level block otherwise, so a list or quote is not opened up by them. */
  insertPaths(paths: string[], x: number, y: number): void {
    if (paths.length === 0) return
    const view = this.editor.ctx.get(editorViewCtx)
    const { state } = view
    const { schema } = state
    const $pos = state.doc.resolve(
      view.posAtCoords({ left: x, top: y })?.pos ?? state.selection.from,
    )
    const paragraphs = paths.map((path) => schema.nodes.paragraph!.create(null, schema.text(path)))
    const tr = state.tr
    let at: number
    if ($pos.depth === 1 && $pos.parent.isTextblock && $pos.parent.content.size === 0) {
      at = $pos.before(1)
      tr.replaceWith(at, $pos.after(1), paragraphs)
    } else {
      at = $pos.depth > 0 ? $pos.after(1) : $pos.pos
      tr.insert(at, paragraphs)
    }
    const end = at + paragraphs.reduce((size, node) => size + node.nodeSize, 0) - 1
    view.dispatch(tr.setSelection(TextSelection.create(tr.doc, end)).scrollIntoView())
    this.focus()
  }

  // Removing a mark at a caret only clears the stored mark, so the whole marked
  // run is selected for the command and the caret put back after it.
  private withMarkRunSelected(mark: MarkType, command: () => void): boolean {
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
    command()
    const caret = Math.min($pos.pos, view.state.doc.content.size)
    view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, caret)))
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
    const { selection, storedMarks } = view.state
    if (!selection.empty) return run()
    // A pending stored mark is only that; the span next to the caret is left alone.
    if (storedMarks) {
      const tr = type.isInSet(storedMarks)
        ? view.state.tr.removeStoredMark(type)
        : view.state.tr.addStoredMark(type.create())
      return view.dispatch(tr)
    }
    if (!type.isInSet(selection.$from.marks()))
      view.dispatch(view.state.tr.addStoredMark(type.create()))
    else this.withMarkRunSelected(type, run)
  }

  private list(kind: 'bulletList' | 'orderedList'): void {
    const view = this.editor.ctx.get(editorViewCtx)
    const { state } = view
    const { $from } = textBounds(state)
    const wanted = kind === 'bulletList' ? 'bullet_list' : 'ordered_list'
    const depth = innermostListDepth($from)
    if (depth == null) {
      const command = kind === 'bulletList' ? wrapInBulletListCommand : wrapInOrderedListCommand
      this.editor.action(callCommand(command.key))
      return
    }
    const list = $from.node(depth)
    if (list.type.name === wanted) {
      this.editor.action(callCommand(liftListItemCommand.key))
      return
    }
    // The items carry the list kind too, and a bullet list whose items say
    // ordered is turned back into one by the preset.
    const pos = $from.before(depth)
    const ordered = wanted === 'ordered_list'
    const attrs = ordered ? { order: 1, spread: list.attrs.spread } : { spread: list.attrs.spread }
    let tr = state.tr.setNodeMarkup(pos, state.schema.nodes[wanted], attrs)
    list.forEach((item, offset) => {
      tr = tr.setNodeMarkup(pos + 1 + offset, undefined, {
        ...item.attrs,
        listType: ordered ? 'ordered' : 'bullet',
        label: ordered ? '1.' : '•',
      })
    })
    view.dispatch(tr)
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
      case 'orderedList':
        this.list(command)
        break
      case 'taskList':
        toggleTaskList(this.editor.ctx)
        break
      case 'link': {
        const payload = typeof arg === 'string' ? { href: arg } : {}
        const toggle = () => run(toggleLinkCommand.key, payload)
        if (
          !state.marks.includes('link') ||
          !this.withMarkRunSelected(linkSchema.type(this.editor.ctx), toggle)
        )
          toggle()
        break
      }
    }
    this.focus()
  }
}
