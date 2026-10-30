import { userMessage } from './diagnostics'
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest'
import {
  InkKitEditor,
  InkKitError,
  type DiagnosticReport,
  type EditorEvents,
  type EditorOptions,
} from '@aicayzer/inkkit'

// The page the app loads, driven as the app drives it: through window.editor, with what the page
// posts to the host collected. InkKit itself is reached only to type, as a key press does.
type Message = Record<string, unknown>
interface Bridge {
  setDiagnosticsEnabled(enabled: boolean): void
  diagnosticReport(): DiagnosticReport & { editorVersion: string }
  load(text: string, generation: number, documentId: string): void
  snapshot(generation: number): Message
  format(name: string, destination: string | null, generation: number): unknown
  moveBlock(direction: 'up' | 'down', generation: number): unknown
  insertImages(
    images: { reference: string; alt: string }[],
    x: number | null,
    y: number | null,
    generation: number,
  ): unknown
  insertPaths(paths: string[], x: number, y: number, generation: number): unknown
  table(name: string, options: null, generation: number): unknown
  pasteAsPlainText(text: string, generation: number): unknown
  replace(search: string, replacement: string, generation: number): unknown
  replaceAll(search: string, replacement: string, generation: number): unknown
  undo(generation: number): unknown
  redo(generation: number): unknown
  setEditingMode(mode: string, generation: number): unknown
  pasteNative(payload: { text: string; generation: number; images: [] }): void
  reload(text: string, generation: number, documentId: string): void
  rebind(generation: number, next: number, documentId: string, nextDocumentId: string): Message
  refresh(
    generation: number,
    next: number,
    documentId: string,
    nextDocumentId: string,
    expectedSource: string,
    text: string,
  ): Message
  clipboard(): Promise<Message>
  imageResponse(requestId: string, value: Record<string, string>): void
  clipboardResponse(requestId: string, value: Record<string, string>): void
  printable(generation: number): Promise<Message>
  setKeymap(keymap: Record<string, string[]>): void
  focus(generation: number): unknown
  blur(generation: number): unknown
  find(text: string, generation: number, direction?: number): unknown
  setFindInset(height: number, generation: number): unknown
  setAccent(color: string): void
}

const posted: Message[] = []
const mount = vi.spyOn(InkKitEditor, 'mount')
let inkkit: InkKitEditor
let events: EditorEvents
let options: EditorOptions | undefined
let generation = 0

const bridge = () => (window as unknown as { editor: Bridge }).editor

beforeAll(async () => {
  document.body.innerHTML = '<div id="editor"></div>'
  Object.assign(window, {
    webkit: {
      messageHandlers: { host: { postMessage: (message: Message) => posted.push(message) } },
    },
  })
  await import('./main')
  inkkit = await (mount.mock.results[0]!.value as Promise<InkKitEditor>)
  events = mount.mock.calls[0]![1]
  options = mount.mock.calls[0]![2]
})

afterAll(async () => {
  await inkkit.destroy()
})

// Indented code, a fence that opens a list item, a fence inside one, and paragraphs InkKit keeps as
// literal Markdown (an unresolved reference, inline HTML): the places a person types in a memo
// written with Windows line endings.
const memo = [
  '# Notes',
  '',
  'Intro __bold__ and * star.',
  '',
  '- ```js',
  '  const a = 1',
  '  ```',
  '- two',
  '',
  'Between.',
  '',
  '- item',
  '',
  '  ```sh',
  '  echo hi',
  '  ```',
  '',
  'Lead',
  '',
  '    indented code',
  '',
  'Plain paragraph',
  '',
  'A [full][ref] note.',
  '',
  'Hello <span>x</span> there.',
  '',
].join('\r\n')

function open(text = memo): void {
  generation += 1
  posted.length = 0
  bridge().load(text, generation, `memo-${generation}`)
}

/** Puts the caret after `text`, or before it, in what the memo reads as. */
function caret(text: string, before = false): void {
  const snapshot = inkkit.textSnapshot(generation)
  const found = snapshot.text.indexOf(text)
  expect(found).toBeGreaterThanOrEqual(0)
  const at = before ? found : found + text.length
  inkkit.selectTextRange({ snapshotId: snapshot.snapshotId, from: at, to: at })
}

/** Selects `text`. */
function select(text: string): void {
  const snapshot = inkkit.textSnapshot(generation)
  const from = snapshot.text.indexOf(text)
  expect(from).toBeGreaterThanOrEqual(0)
  inkkit.selectTextRange({ snapshotId: snapshot.snapshotId, from, to: from + text.length })
}

/** What the host holds after a key: a snapshot, never a refusal. */
function saved(): string {
  const snapshot = bridge().snapshot(generation)
  expect(snapshot).not.toHaveProperty('snapshotError')
  return snapshot.text as string
}

const of = (type: string) => posted.filter((message) => message.type === type)

describe('typing into a memo with Windows line endings', () => {
  it('reports ready and holds the memo as loaded', () => {
    expect(of('ready')).toHaveLength(1)
    open()
    expect(saved()).toBe(memo)
  })

  // Typed text lands in the memo as typed, except in indented code, which InkKit writes fenced.
  const inPlace = (after: string) => (typed: string) => {
    const at = memo.indexOf(after) + after.length
    return memo.slice(0, at) + typed + memo.slice(at)
  }
  const places: [name: string, after: string, typed: string, saves: (typed: string) => string][] = [
    ['a code block that opens a list item', 'const a = 1', 'Z * _ [a] <b>', inPlace('const a = 1')],
    ['a code block inside a list item', 'echo hi', 'Z * _ [a] <b>', inPlace('echo hi')],
    [
      'an indented code block',
      'indented code',
      'Z * _ [a] <b>',
      (typed) => memo.replace('    indented code', `\`\`\`\r\nindented code${typed}\r\n\`\`\``),
    ],
    [
      'a paragraph kept as literal Markdown',
      'A [full][ref] note.',
      ' *a* _b_ [c] <d> `e` #f',
      inPlace('A [full][ref] note.'),
    ],
    ['a paragraph holding inline HTML', 'there.', ' *a* _b_ [c] <d>', inPlace('there.')],
  ]

  for (const [name, after, typed, saves] of places)
    it(`saves every key typed into ${name}`, () => {
      open()
      caret(after)
      let last = 0
      for (const [index, character] of [...typed].entries()) {
        expect(inkkit.insertText(character, generation)).toBe(true)
        const expected = saves(typed.slice(0, index + 1))
        expect(saved()).toBe(expected)
        const changed = of('changed').at(-1)
        expect(changed).toMatchObject({ markdown: expected, generation })
        expect(changed!.sequence as number).toBeGreaterThan(last)
        last = changed!.sequence as number
      }
      expect(of('editorWarning')).toEqual([])
      expect(of('error')).toEqual([])
    })

  it('saves the code block that three backticks and a space make, in the same line endings', () => {
    open()
    caret('Plain paragraph', true)
    for (const character of '``` ') {
      expect(inkkit.insertText(character, generation)).toBe(true)
      saved()
    }
    expect(saved()).toBe(memo.replace('Plain paragraph\r\n', '```\r\nPlain paragraph\r\n```\r\n'))
    expect(of('editorWarning')).toEqual([])
  })
})

describe('formatting', () => {
  it('reports each heading level as available, as the menu reads it', () => {
    open()
    caret('Plain paragraph')
    const state = of('commandState').at(-1)
    expect(state).toMatchObject({ generation, documentId: `memo-${generation}` })
    const formats = (state!.commands as { format: Record<string, boolean> }).format
    for (const level of [1, 2, 3, 4, 5, 6]) expect(formats[`heading${level}`]).toBe(true)
    expect(formats).not.toHaveProperty('heading')
  })

  it('makes the block a heading by its level', () => {
    open()
    caret('Plain paragraph')
    expect(bridge().format('heading2', null, generation)).toBe(true)
    expect(saved()).toBe(memo.replace('Plain paragraph', '## Plain paragraph'))
  })

  it('links the text only to an address it can open', () => {
    open()
    select('Plain paragraph')
    expect(bridge().format('link', 'https://example.com', generation)).toBe(true)
    expect(saved()).toContain('[Plain paragraph](https://example.com)')
  })

  it('puts the caret state in the command state alone', () => {
    open()
    caret('Plain paragraph')
    expect(of('state')).toEqual([])
    expect(of('commandState').at(-1)).toHaveProperty('caret.block.type', 'paragraph')
  })
})

describe('an edit that InkKit refuses', () => {
  const picture = `images/${'a'.repeat(64)}.png`
  // Every entry the app sends an edit through, refused as another memo's, and with the message
  // the app shows the person: native code shows `message` as it arrives.
  const other = 'Document changed'
  const stale = [
    ['a format', () => bridge().format('bold', null, generation - 1)],
    ['a block move', () => bridge().moveBlock('up', generation - 1)],
    ['a table command', () => bridge().table('insert', null, generation - 1)],
    ['a plain text paste', () => bridge().pasteAsPlainText('x', generation - 1)],
    ['a replacement', () => bridge().replace('Plain', 'Simple', generation - 1)],
    ['a replacement of all', () => bridge().replaceAll('Plain', 'Simple', generation - 1)],
    ['an undo', () => bridge().undo(generation - 1)],
    ['a redo', () => bridge().redo(generation - 1)],
    ['a change of mode', () => bridge().setEditingMode('source', generation - 1)],
    [
      'images',
      () => bridge().insertImages([{ reference: picture, alt: 'Pic' }], null, null, generation - 1),
    ],
    ['paths', () => bridge().insertPaths(['/Users/a/File.txt'], 10, 10, generation - 1)],
  ] as const
  const refusals = [
    ...stale.map(
      ([name, call]) => [`${name} for another memo`, call, 'stale-document', other] as const,
    ),
    [
      'a link to an address that cannot open',
      () => bridge().format('link', 'javascript:alert(1)', generation),
      'invalid-argument',
      'options.destination must be relative, or an address with an allowed scheme (http, https, mailto, tel or one of linkSchemes), with no control characters',
    ],
  ] as const

  for (const [name, call, code, message] of refusals)
    it(`comes back to the host with its reason: ${name}`, () => {
      open()
      caret('Plain paragraph')
      expect(call()).toMatchObject({
        commandError: code,
        code,
        message: userMessage(code),
        generation,
      })
      expect(JSON.stringify(call())).not.toContain(message)
      expect(bridge().snapshot(generation)).toMatchObject({ text: memo, dirty: false })
    })

  for (const [name, call] of [
    ['paths', () => bridge().insertPaths(['/Users/a/File.txt'], 10, 10, generation)],
    [
      'images',
      () => bridge().insertImages([{ reference: picture, alt: 'Pic' }], null, null, generation),
    ],
    ['a format', () => bridge().format('bold', null, generation)],
    ['a block move', () => bridge().moveBlock('up', generation)],
  ] as const)
    it(`comes back while text is being composed: ${name}`, () => {
      open()
      caret('Plain paragraph')
      document
        .querySelector('.ProseMirror')!
        .dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true }))
      expect(call()).toMatchObject({
        commandError: 'composition',
        code: 'composition',
        generation,
        message: 'Finish entering text before trying again.',
      })
      document
        .querySelector('.ProseMirror')!
        .dispatchEvent(new CompositionEvent('compositionend', { bubbles: true }))
      expect(saved()).toBe(memo)
    })

  const table = '| a | b |\r\n| - | - |\r\n| x | y |\r\n'
  const preservation = 'The edited Markdown cannot be reopened without changing its content'
  for (const [name, call, cell] of [
    ['a replacement', () => bridge().replace('x', 'x\ny', generation), 'x<br />y'],
    ['a replacement of all', () => bridge().replaceAll('x', 'x\ny', generation), 'x<br />y'],
    ['a plain text paste', () => bridge().pasteAsPlainText('p\nq', generation), 'p<br />q'],
  ] as const)
    it(`preserves table cell line breaks from ${name}`, () => {
      open(table)
      select('x')
      expect(call()).toBeTruthy()
      expect(saved()).toBe(table.replace('x', cell))
    })

  it('reaches the host as a warning when a native paste could not be preserved', async () => {
    open(table)
    select('x')
    bridge().pasteNative({ text: 'p\nq', generation, images: [] })
    await vi.waitFor(() => expect(of('editorWarning')).toHaveLength(1))
    expect(of('editorWarning')[0]).toMatchObject({
      type: 'editorWarning',
      code: 'preservation',
      generation,
      message: 'That edit couldn’t be applied. Your previous text is unchanged.',
    })
    expect(saved()).toBe(table)
  })

  it('does not stop an accepted one: images and paths land where the caret is', () => {
    open()
    caret('Between.')
    expect(
      bridge().insertImages([{ reference: picture, alt: 'Pic' }], null, null, generation),
    ).toBe(true)
    expect(bridge().insertPaths(['/Users/a/File.txt'], 0, 0, generation)).toBe(true)
    const text = saved()
    expect(text).toContain(`![Pic](${picture})`)
    expect(text).toContain('/Users/a/File.txt')
  })

  it('reaches the host as a warning when a native paste is for another memo', async () => {
    open()
    bridge().pasteNative({ text: 'Stale', generation: generation - 1, images: [] })
    await vi.waitFor(() => expect(of('editorWarning')).toHaveLength(1))
    expect(of('editorWarning')[0]).toMatchObject({
      type: 'editorWarning',
      code: 'stale-document',
      generation: generation - 1,
      message: 'Your memo changed. Try again.',
    })
    expect(saved()).toBe(memo)
  })

  it('pastes into the memo it was made for', async () => {
    open()
    caret('Between.')
    bridge().pasteNative({ text: ' Pasted', generation, images: [] })
    await vi.waitFor(() => expect(saved()).toContain('Between. Pasted'))
    expect(of('editorWarning')).toEqual([])
  })
})

describe('a memo that is reloaded, recovered or refreshed', () => {
  it('moves to the new generation and refuses the old one', () => {
    open()
    const previous = generation
    generation += 1
    bridge().reload(`${memo}Added.\r\n`, generation, `memo-${previous}`)
    expect(saved()).toBe(`${memo}Added.\r\n`)
    expect(bridge().snapshot(previous)).toMatchObject({ snapshotError: 'stale-document' })
  })

  it('keeps what was typed when it is rebound to a new identity', () => {
    open()
    caret('Between.')
    expect(inkkit.insertText('!', generation)).toBe(true)
    const previous = generation
    generation += 1
    const result = bridge().rebind(previous, generation, `memo-${previous}`, 'recovered')
    expect(result).toMatchObject({ documentId: 'recovered', generation })
    expect(result.text).toBe(memo.replace('Between.', 'Between.!'))
    expect(saved()).toBe(result.text)
  })

  it('replaces only a source that nobody has edited', () => {
    open()
    const previous = generation
    caret('Between.')
    inkkit.insertText('!', generation)
    const edited = bridge().refresh(
      previous,
      previous + 1,
      `memo-${previous}`,
      'next',
      memo,
      'External\r\n',
    )
    expect(edited).toMatchObject({ applied: false, text: memo.replace('Between.', 'Between.!') })
    expect(saved()).toBe(memo.replace('Between.', 'Between.!'))
    generation += 1
    const live = memo.replace('Between.', 'Between.!')
    const applied = bridge().refresh(
      previous,
      generation,
      `memo-${previous}`,
      'next',
      live,
      'External\r\n',
    )
    expect(applied).toMatchObject({ applied: true, text: 'External\r\n', generation })
    expect(saved()).toBe('External\r\n')
  })

  it('tells the person when a copied image could not be read', async () => {
    open()
    const copying = events.clipboard!({
      documentId: `memo-${generation}`,
      generation,
      revision: 0,
      text: 'Before',
      html: '<p>Before</p>',
      markdown: 'Before',
      images: [{ reference: 'images/gone.png', alt: 'Gone', error: 'Image bytes unavailable' }],
      diagrams: [],
    })
    expect(of('editorWarning')).toHaveLength(1)
    const [request] = of('writeClipboard')
    expect(request).toMatchObject({ text: 'Before', images: [] })
    bridge().clipboardResponse(request!.requestId as string, {})
    await copying
  })

  it('tells the person when a copied diagram could not be exported', async () => {
    open()
    const copying = events.clipboard!({
      documentId: `memo-${generation}`,
      generation,
      revision: 0,
      text: 'Before',
      html: '<p>Before</p>',
      markdown: 'Before',
      images: [],
      diagrams: [{ source: 'flowchart LR\nA-->B', error: 'Diagram could not be rendered' }],
    })
    expect(of('editorWarning')).toEqual([
      {
        type: 'editorWarning',
        message: 'Some copied diagrams were unavailable; their source was retained',
      },
    ])
    const [request] = of('writeClipboard')
    bridge().clipboardResponse(request!.requestId as string, {})
    await copying
  })

  it('copies and prints the memo it holds', async () => {
    open()
    const copy = await bridge().clipboard()
    expect(copy).toMatchObject({ generation, documentId: `memo-${generation}` })
    expect(copy.text).toContain('Plain paragraph')
    expect(await bridge().printable(generation)).toMatchObject({ generation })
  })
})

describe('the page', () => {
  it('takes every key binding the app sends', () => {
    open()
    const keys = [
      'heading1',
      'heading2',
      'heading3',
      'paragraph',
      'bold',
      'italic',
      'strikethrough',
      'code',
      'codeBlock',
      'quote',
      'bulletList',
      'orderedList',
      'taskList',
    ]
    expect(() =>
      bridge().setKeymap(Object.fromEntries(keys.map((name) => [name, ['Mod-Alt-9']]))),
    ).not.toThrow()
  })

  it('scopes focus to the memo it was asked about', () => {
    open()
    expect(bridge().focus(generation)).toBeUndefined()
    expect(bridge().blur(generation)).toBeUndefined()
    expect(bridge().blur(generation - 1)).toMatchObject({ commandError: 'stale-document' })
  })

  it('takes the accent through InkKit’s token', () => {
    bridge().setAccent('#ff8800')
    expect(document.documentElement.style.getPropertyValue('--inkkit-accent-color')).toBe('#ff8800')
  })
})

describe('Memos editing preferences and block commands', () => {
  it('disables smart punctuation and slash commands without note suggestions', () => {
    expect(options).toMatchObject({
      textInput: { smartPunctuation: false },
      slashMenu: { enabled: false },
    })
    expect(options).not.toHaveProperty('wikiLinks')
  })

  it('moves CRLF blocks through the bridge and reports availability to the host', () => {
    open('First\r\n\r\nSecond\r\n')
    caret('Second')
    expect(of('commandState').at(-1)).toMatchObject({
      documentId: `memo-${generation}`,
      generation,
      commands: { moveBlockUp: true, moveBlockDown: false },
    })
    expect(bridge().moveBlock('up', generation)).toBe(true)
    expect(saved()).toBe('Second\r\n\r\nFirst\r\n')
    expect(of('changed').at(-1)).toMatchObject({ markdown: saved(), generation })
    expect(of('commandState').at(-1)).toMatchObject({
      commands: { moveBlockUp: false, moveBlockDown: true },
    })
    expect(bridge().moveBlock('down', generation)).toBe(true)
    expect(saved()).toBe('First\r\n\r\nSecond\r\n')
    bridge().undo(generation)
    expect(saved()).toBe('Second\r\n\r\nFirst\r\n')
    bridge().redo(generation)
    expect(saved()).toBe('First\r\n\r\nSecond\r\n')
    bridge().setEditingMode('source', generation)
    expect(bridge().moveBlock('up', generation)).toBe(false)
    expect(saved()).toBe('First\r\n\r\nSecond\r\n')
  })
})

describe('native viewport and counts', () => {
  it('registers the fade and formatting chrome as viewport insets', () => {
    expect(inkkit.viewport().insets).toEqual({ top: 24, right: 0, bottom: 96, left: 0 })
  })

  it('counts readable graphemes and words with memo scope', async () => {
    open('**Hello** café 👨‍👩‍👧‍👦\n\n<!-- hidden -->')
    await Promise.resolve()
    const snapshot = inkkit.textSnapshot(generation)
    expect(snapshot.text).toBe('Hello café 👨‍👩‍👧‍👦')
    expect(of('textCounts').at(-1)).toMatchObject({
      documentId: snapshot.documentId,
      generation,
      characters: 12,
      words: 2,
    })
    bridge().setEditingMode('source', generation)
    await Promise.resolve()
    expect(of('textCounts').at(-1)?.characters).toBeGreaterThan(12)
    bridge().setEditingMode('formatted', generation)
    await Promise.resolve()
    expect(of('textCounts').at(-1)?.characters).toBe(12)
  })
})

describe('native image storage', () => {
  it('sends only serializable document context when imports include an AbortSignal', async () => {
    open('')
    const signal = new AbortController().signal
    const pending = options!.images!.importImage(
      { bytes: new Uint8Array([137, 80, 78, 71]), mimeType: 'image/png', filename: 'picture.png' },
      { documentId: `memo-${generation}`, generation, operationId: 'image-import', signal },
    )
    const request = of('imageRequest').at(-1)!
    bridge().imageResponse(request.requestId as string, { reference: 'images/imported.png' })
    await expect(pending).resolves.toEqual({ reference: 'images/imported.png' })
    expect(request).toEqual({
      type: 'imageRequest',
      action: 'import',
      requestId: expect.any(String),
      documentId: `memo-${generation}`,
      generation,
      bytesBase64: 'iVBORw==',
      mimeType: 'image/png',
      filename: 'picture.png',
    })
    expect(request).not.toHaveProperty('signal')
  })

  it('hands an image context menu request to the host, at the point in the page', () => {
    open('')
    const reference = `images/${'a'.repeat(64)}.png`
    options!.images!.contextMenu!(
      reference,
      { clientX: 12.5, clientY: 40 },
      { documentId: `memo-${generation}`, generation, operationId: 'image-menu' },
    )
    expect(of('imageMenu').at(-1)).toEqual({ type: 'imageMenu', reference, x: 12.5, y: 40 })
  })
})

describe('safe global error classification', () => {
  it('does not forward writing from script errors or unhandled promise rejections', () => {
    open()
    const canary = 'PRIVATE memo text filename /private/memo.md'
    window.dispatchEvent(new ErrorEvent('error', { message: canary, error: new Error(canary) }))
    const rejection = new Event('unhandledrejection')
    Object.defineProperty(rejection, 'reason', { value: new Error(canary) })
    window.dispatchEvent(rejection)
    expect(of('error')).toEqual([
      { type: 'error', classification: 'script-error' },
      { type: 'error', classification: 'unhandled-rejection' },
    ])
    expect(JSON.stringify(of('error'))).not.toContain(canary)
  })
})

describe('local diagnostic reports', () => {
  it('records only while enabled and reports without a successful snapshot', () => {
    open('PRIVATE source canary\r\n')
    expect(bridge().diagnosticReport()).toMatchObject({ enabled: false, events: [] })
    expect(bridge().diagnosticReport().editorVersion).toMatch(/^\d+\.\d+\.\d+$/)
    bridge().setDiagnosticsEnabled(true)
    const root = document.getElementById('editor')!
    root.dispatchEvent(
      new InputEvent('beforeinput', {
        data: 'PRIVATE replacement canary',
        inputType: 'insertReplacementText',
        bubbles: true,
      }),
    )
    const snapshot = inkkit.snapshot.bind(inkkit)
    try {
      inkkit.snapshot = () => {
        throw new InkKitError('composition', 'PRIVATE technical exception')
      }
      expect(bridge().snapshot(generation)).toMatchObject({
        snapshotError: 'composition',
        code: 'composition',
        generation,
      })
      const report = bridge().diagnosticReport()
      expect(report).toMatchObject({ schemaVersion: 1, enabled: true, state: { generation } })
      expect(report.events.some((event) => event.kind === 'input')).toBe(true)
      expect(JSON.stringify(report)).not.toContain('PRIVATE')
      expect(JSON.stringify(report)).not.toContain(`memo-${generation}`)
    } finally {
      inkkit.snapshot = snapshot
      bridge().setDiagnosticsEnabled(false)
    }
    expect(bridge().diagnosticReport()).toMatchObject({ enabled: false, events: [] })
    expect(bridge().diagnosticReport().incident).toBeUndefined()
    expect(saved()).toBe('PRIVATE source canary\r\n')
  })
})

describe('native find controls', () => {
  const state = () => of('searchState').at(-1)

  it('navigates both directions, wraps, and keeps query updates on the current match', () => {
    open('Garden garden GARDEN\n')
    caret('Garden', true)
    expect(bridge().find('garden', generation)).toBe(true)
    expect(state()).toMatchObject({ query: 'garden', current: 1, total: 3, generation })
    bridge().find('garden', generation, -1)
    expect(state()).toMatchObject({ current: 3, total: 3 })
    bridge().find('garden', generation, 1)
    expect(state()).toMatchObject({ current: 1, total: 3 })
    bridge().find('garden', generation)
    expect(state()).toMatchObject({ current: 1, total: 3 })
    expect(saved()).toBe('Garden garden GARDEN\n')
  })

  it('advances past an unchanged replacement without adding history', () => {
    open('memo memo\n')
    caret('memo', true)
    bridge().find('memo', generation)
    const revision = inkkit.snapshot(generation).revision
    expect(bridge().replace('memo', 'memo', generation)).toBe(false)
    expect(state()).toMatchObject({ current: 2, total: 2 })
    expect(inkkit.snapshot(generation).revision).toBe(revision)
  })

  it('restores query and selection when replacement is refused', () => {
    open('memo note memo\n')
    bridge().find('memo', generation)
    const before = inkkit.textSnapshot(generation)
    const beforeState = state()
    const replace = vi.spyOn(inkkit, 'replace').mockImplementationOnce(() => {
      throw new InkKitError('preservation', 'Refused edit')
    })
    try {
      expect(bridge().replace('note', 'changed', generation)).toMatchObject({
        commandError: 'preservation',
      })
      expect(inkkit.textSnapshot(generation).selection).toEqual(before.selection)
      expect(state()).toEqual(beforeState)
      expect(saved()).toBe('memo note memo\n')
    } finally {
      replace.mockRestore()
    }
  })

  it('reuses match ranges while only the caret changes', async () => {
    open('memo memo\n')
    const matches = vi.spyOn(inkkit, 'searchMatches')
    try {
      bridge().find('memo', generation)
      const calls = matches.mock.calls.length
      bridge().find('memo', generation, 1)
      await Promise.resolve()
      expect(matches).toHaveBeenCalledTimes(calls)
    } finally {
      matches.mockRestore()
    }
  })

  it('replaces the indicated match, accepts an empty replacement, and refreshes after undo', async () => {
    open('Garden garden GARDEN\r\n')
    caret('Garden', true)
    bridge().find('garden', generation)
    bridge().find('garden', generation, 1)
    bridge().replace('garden', '$&', generation)
    expect(saved()).toBe('Garden $& GARDEN\r\n')
    expect(state()).toMatchObject({ current: 2, total: 2 })
    bridge().replace('garden', '', generation)
    // The serializer preserves the new trailing space as an entity in Markdown.
    expect(saved()).toBe('Garden $&&#x20;\r\n')
    bridge().undo(generation)
    await Promise.resolve()
    expect(saved()).toBe('Garden $& GARDEN\r\n')
    expect(state()).toMatchObject({ total: 2 })
  })

  it('counts only engine-searchable text, without image labels or cross-block matches', () => {
    open('needle\n\n![needle](images/missing.png)\n\nneedle\n')
    bridge().find('needle', generation)
    expect(state()).toMatchObject({ total: 2 })
    bridge().find('needle\nneedle', generation)
    expect(state()).toMatchObject({ total: 0, current: 0 })
  })

  it('preserves Unicode offsets and literal punctuation', () => {
    open('İ a.b 🙂 a.b\n')
    bridge().find('a.b', generation)
    expect(state()).toMatchObject({ total: 2 })
    bridge().find('a.b', generation, -1)
    bridge().replace('a.b', 'é', generation)
    expect(saved()).toBe('İ a.b 🙂 é\n')
  })

  it('clears empty and missing searches and rejects an obsolete generation', () => {
    open('memo memo\n')
    bridge().find('memo', generation)
    const oldGeneration = generation
    open('new memo\n')
    expect(state()).toMatchObject({ query: '', current: 0, total: 0, generation })
    expect(bridge().find('old', oldGeneration)).toMatchObject({ commandError: 'stale-document' })
    expect(state()).toMatchObject({ query: '', generation })
    bridge().find('missing', generation)
    expect(state()).toMatchObject({ current: 0, total: 0 })
    bridge().find('', generation)
    expect(state()).toMatchObject({ query: '', current: 0, total: 0 })
  })

  it('retains native search focus while navigating and replacing', () => {
    open('memo memo\n')
    const input = document.createElement('input')
    document.body.append(input)
    input.focus()
    bridge().find('memo', generation)
    bridge().find('memo', generation, 1)
    bridge().replace('memo', 'note', generation)
    expect(document.activeElement).toBe(input)
    input.remove()
  })

  it('updates counts after typing and mode changes, and restores highlights after reload', async () => {
    open('**memo** memo\n')
    bridge().find('memo', generation)
    bridge().replaceAll('memo', 'note', generation)
    expect(state()).toMatchObject({ total: 0, current: 0 })
    bridge().undo(generation)
    await Promise.resolve()
    expect(state()).toMatchObject({ total: 2 })
    bridge().setEditingMode('source', generation)
    await Promise.resolve()
    bridge().find('**', generation)
    expect(state()).toMatchObject({ total: 2 })
    bridge().setEditingMode('formatted', generation)
    await Promise.resolve()
    expect(state()).toMatchObject({ total: 0 })
    bridge().find('memo', generation)
    const text = saved()
    generation += 1
    bridge().reload(text, generation, `memo-${generation}`)
    expect(state()).toMatchObject({ query: 'memo', total: 2, generation })
  })

  it('guards the find inset against invalid and stale updates', () => {
    open('memo\n')
    expect(bridge().setFindInset(80, generation)).toBeUndefined()
    expect(
      document
        .querySelector<HTMLElement>('#editor')
        ?.style.getPropertyValue('--inkkit-padding-top'),
    ).toBe('88px')
    expect(bridge().setFindInset(0, generation)).toBeUndefined()
    expect(
      document
        .querySelector<HTMLElement>('#editor')
        ?.style.getPropertyValue('--inkkit-padding-top'),
    ).toBe('24px')
    expect(bridge().setFindInset(-1, generation)).toMatchObject({
      commandError: 'invalid-argument',
    })
    expect(bridge().setFindInset(80, generation - 1)).toMatchObject({
      commandError: 'stale-document',
    })
  })
})
