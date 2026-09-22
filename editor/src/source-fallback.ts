import type { MemoEditor, FormatCommand, InsertedImage, Keymap } from './editor'

type FormattedEditor = Pick<
  MemoEditor,
  | 'load'
  | 'reload'
  | 'canonicalMarkdown'
  | 'markdown'
  | 'focus'
  | 'format'
  | 'insertPaths'
  | 'insertImages'
  | 'setKeymap'
>

/** A file the visual editor would normalize is edited as source. This deliberately errs on preserving
 * bytes: metadata, unsupported syntax and unfamiliar formatting never disappear on the first edit. */
export class SourceFallback {
  private readonly source = document.createElement('textarea')
  private readonly pane = document.createElement('div')
  private baseline = ''
  private generation = 0
  private sourceMode = false
  private edited = false
  private lineEnding = '\n'

  constructor(
    private readonly formatted: FormattedEditor,
    private readonly formattedRoot: HTMLElement,
    root: HTMLElement,
    private readonly changed: (markdown: string, generation: number) => void,
  ) {
    this.pane.className = 'source-pane'
    const label = document.createElement('div')
    label.className = 'source-label'
    label.textContent = 'Source editing preserves this file’s Markdown.'
    this.source.setAttribute('aria-label', 'Markdown source')
    this.source.spellcheck = false
    this.pane.append(label, this.source)
    root.append(this.pane)
    this.pane.hidden = true
    this.source.addEventListener('input', () => {
      this.edited = true
      this.changed(this.sourceMarkdown(), this.generation)
    })
  }

  load(markdown: string, generation: number): void {
    this.display(markdown, generation, false)
  }

  reload(markdown: string, generation: number): void {
    this.display(markdown, generation, true)
  }

  private display(markdown: string, generation: number, keepCaret: boolean): void {
    const caret = this.source.selectionStart
    const scroll = this.source.scrollTop
    this.edited = false
    this.lineEnding =
      markdown.includes('\r\n') && !markdown.replaceAll('\r\n', '').includes('\n') ? '\r\n' : '\n'
    this.baseline = markdown
    this.generation = generation
    try {
      if (keepCaret) this.formatted.reload(markdown, generation)
      else this.formatted.load(markdown, generation)
      this.sourceMode = this.formatted.canonicalMarkdown() !== markdown
    } catch {
      // The source remains fully editable even when the formatted parser cannot read the document.
      this.sourceMode = true
    }
    this.formattedRoot.hidden = this.sourceMode
    this.pane.hidden = !this.sourceMode
    this.source.value = markdown
    this.source.setSelectionRange(
      keepCaret ? Math.min(caret, markdown.length) : markdown.length,
      keepCaret ? Math.min(caret, markdown.length) : markdown.length,
    )
    if (keepCaret) this.source.scrollTop = scroll
  }

  markdown(): string | null {
    if (!this.sourceMode) return this.formatted.markdown()
    return !this.edited || this.sourceMarkdown() === this.baseline ? null : this.sourceMarkdown()
  }

  focus(): void {
    if (this.sourceMode) this.source.focus()
    else this.formatted.focus()
  }

  format(command: FormatCommand, arg?: string | number): void {
    if (!this.sourceMode) return this.formatted.format(command, arg)
    const selected = this.source.value.slice(this.source.selectionStart, this.source.selectionEnd)
    const wrap = (mark: string) => mark + selected + mark
    const replacements: Record<FormatCommand, string> = {
      bold: wrap('**'),
      italic: wrap('*'),
      strikethrough: wrap('~~'),
      code: wrap('`'),
      codeBlock: '\n```' + (arg ?? '') + '\n' + selected + '\n```\n',
      heading: '#'.repeat(Number(arg) || 1) + ' ' + selected,
      paragraph: selected,
      quote: '> ' + selected.replaceAll('\n', '\n> '),
      bulletList: '- ' + selected.replaceAll('\n', '\n- '),
      orderedList: '1. ' + selected.replaceAll('\n', '\n1. '),
      taskList: '- [ ] ' + selected.replaceAll('\n', '\n- [ ] '),
      link: '[' + selected + '](' + (arg ?? 'https://') + ')',
    }
    this.insert(replacements[command])
  }

  insertPaths(paths: string[], x: number, y: number): void {
    if (!this.sourceMode) return this.formatted.insertPaths(paths, x, y)
    this.insert(paths.join('\n\n'))
  }

  insertImages(images: InsertedImage[], x: number | null, y: number | null): void {
    if (!this.sourceMode) return this.formatted.insertImages(images, x, y)
    this.insert(
      images
        .map((image) => '![' + image.alt.replaceAll(']', '\\]') + '](' + image.path + ')')
        .join('\n\n'),
    )
  }

  setKeymap(keymap: Keymap): void {
    this.formatted.setKeymap(keymap)
  }

  private sourceMarkdown(): string {
    return this.source.value.replaceAll('\n', this.lineEnding)
  }

  private insert(text: string): void {
    this.source.setRangeText(text, this.source.selectionStart, this.source.selectionEnd, 'end')
    this.edited = true
    this.changed(this.sourceMarkdown(), this.generation)
    this.source.focus()
  }
}
