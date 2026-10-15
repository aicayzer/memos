import {
  InkKitEditor,
  InkKitError,
  type CapturedImage,
  type ClipboardOutput,
  type DocumentContext,
  type FormatCommand,
  type ImageAdapter,
  type ImageInsertion,
  type PortableImage,
} from '@aicayzer/inkkit'
import '@aicayzer/inkkit/style.css'
import './style.css'

function post(message: Record<string, unknown>): void {
  const host = (
    window as unknown as {
      webkit?: { messageHandlers?: { host?: { postMessage(message: unknown): void } } }
    }
  ).webkit?.messageHandlers?.host
  if (host) host.postMessage(message)
}

const root = document.getElementById('editor')
if (!root) throw new Error('editor root missing')
const retryableSnapshotCodes = new Set([
  'not-ready',
  'stale-document',
  'composition',
  'operation-pending',
  'preservation',
])
let generation = 0
let changeSequence = 0
const replies = new Map<
  string,
  { resolve(value: Record<string, string>): void; reject(error: Error): void }
>()
function imageRequest(
  action: string,
  context: DocumentContext,
  fields: Record<string, unknown>,
): Promise<Record<string, string>> {
  const requestId = crypto.randomUUID()
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      replies.delete(requestId)
      reject(new Error('Image request timed out'))
    }, 15000)
    replies.set(requestId, {
      resolve(value) {
        clearTimeout(timeout)
        resolve(value)
      },
      reject(error) {
        clearTimeout(timeout)
        reject(error)
      },
    })
    post({ type: 'imageRequest', action, requestId, ...context, ...fields })
  })
}
function encode(bytes: Uint8Array): string {
  let binary = ''
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary)
}
function decode(value: string): Uint8Array {
  return Uint8Array.from(atob(value), (character) => character.charCodeAt(0))
}
const images: ImageAdapter = {
  presentation(reference) {
    return /^images\/[0-9a-f]{64}\.(?:png|jpg|gif|webp)$/.test(reference)
      ? { url: `memo-image://memo/${reference}` }
      : undefined
  },
  async importImage(input: CapturedImage, context: DocumentContext) {
    const reply = await imageRequest('import', context, {
      bytesBase64: encode(input.bytes),
      mimeType: input.mimeType,
      filename: input.filename,
    })
    if (!reply.reference) throw new Error('Image import returned no reference')
    return { reference: reply.reference }
  },
  async exportImage(reference: string, context: DocumentContext): Promise<PortableImage> {
    const reply = await imageRequest('export', context, { reference })
    if (!reply.bytesBase64 || !reply.mimeType) throw new Error('Image bytes unavailable')
    return { bytes: decode(reply.bytesBase64), mimeType: reply.mimeType }
  },
}
function writeClipboard(output: ClipboardOutput): Promise<void> {
  // InkKit describes degraded output in the output itself and no longer reports it as an error.
  if (output.images.some((slot) => slot.error))
    post({
      type: 'editorWarning',
      message: 'Some copied images were unavailable; their descriptions were retained',
    })
  const requestId = crypto.randomUUID()
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      replies.delete(requestId)
      reject(new Error('Clipboard write timed out'))
    }, 15000)
    replies.set(requestId, {
      resolve() {
        clearTimeout(timeout)
        resolve()
      },
      reject(error) {
        clearTimeout(timeout)
        reject(error)
      },
    })
    post({
      type: 'writeClipboard',
      requestId,
      documentId: output.documentId,
      generation: output.generation,
      text: output.text,
      html: output.html,
      images: output.images.flatMap((slot) =>
        slot.image
          ? [
              {
                bytesBase64: encode(slot.image.bytes),
                mimeType: slot.image.mimeType,
                alt: slot.alt,
              },
            ]
          : [],
      ),
    })
  })
}
const editor = await InkKitEditor.mount(
  root,
  {
    changed(snapshot) {
      post({
        type: 'changed',
        markdown: snapshot.text,
        generation: snapshot.generation,
        sequence: ++changeSequence,
      })
    },
    commandStateChanged(state) {
      post({ type: 'commandState', ...state })
    },
    openLink(href) {
      post({ type: 'openLink', href })
    },
    copy(text) {
      post({ type: 'copy', text })
    },
    error(error) {
      post({ type: 'editorWarning', message: error.message })
    },
    clipboard: writeClipboard,
  },
  { images },
)
function command<T>(operation: () => T): T | { commandError: string; message: string } {
  try {
    return operation()
  } catch (error) {
    // Expected command guards must not poison the native document through a global script error.
    if (error instanceof InkKitError) return { commandError: error.code, message: error.message }
    throw error
  }
}
const facade = {
  load(text: string, nextGeneration: number, documentId = String(nextGeneration)) {
    editor.loadDocument({ text, generation: nextGeneration, documentId, format: 'md' })
    generation = nextGeneration
  },
  reload(text: string, nextGeneration: number, documentId = String(nextGeneration)) {
    editor.reloadDocument({ text, generation: nextGeneration, documentId, format: 'md' })
    generation = nextGeneration
  },
  rebind(
    expectedGeneration: number,
    nextGeneration: number,
    expectedDocumentId: string,
    documentId: string,
  ) {
    if (generation !== expectedGeneration) throw new Error('The memo changed')
    let snapshot: ReturnType<InkKitEditor['snapshot']>
    try {
      snapshot = editor.snapshot(expectedGeneration)
    } catch (error) {
      if (!(error instanceof InkKitError) || !retryableSnapshotCodes.has(error.code)) throw error
      return {
        rejected: true,
        snapshotError: error.code,
        generation,
        documentId: expectedDocumentId,
        message: String(error),
      }
    }
    if (snapshot.documentId !== expectedDocumentId) throw new Error('The memo changed')
    editor.reloadDocument({
      text: snapshot.text,
      generation: nextGeneration,
      documentId,
      format: 'md',
    })
    generation = nextGeneration
    return { ...snapshot, generation: nextGeneration, documentId }
  },
  refresh(
    expectedGeneration: number,
    nextGeneration: number,
    expectedDocumentId: string,
    documentId: string,
    expectedSource: string,
    text: string,
  ) {
    if (generation !== expectedGeneration) throw new Error('The memo changed')
    let snapshot: ReturnType<InkKitEditor['snapshot']>
    try {
      snapshot = editor.snapshot(expectedGeneration)
    } catch (error) {
      if (!(error instanceof InkKitError) || !retryableSnapshotCodes.has(error.code)) throw error
      return {
        rejected: true,
        snapshotError: error.code,
        generation,
        documentId: expectedDocumentId,
        message: String(error),
      }
    }
    if (snapshot.documentId !== expectedDocumentId) throw new Error('The memo changed')
    if (snapshot.text !== expectedSource)
      return { ...snapshot, applied: false, sequence: changeSequence }
    editor.reloadDocument({ text, generation: nextGeneration, documentId, format: 'md' })
    generation = nextGeneration
    return { text, applied: true, generation: nextGeneration, documentId, sequence: changeSequence }
  },
  snapshot(expectedGeneration: number) {
    try {
      return editor.snapshot(expectedGeneration)
    } catch (error) {
      // An expected rejection must not reach WKWebView's global script-error listener.
      if (error instanceof InkKitError) return { snapshotError: error.code, message: error.message }
      throw error
    }
  },
  clipboard: () => editor.clipboardSnapshot('document', generation),
  format: (name: FormatCommand, destination: string | null, expected: number) =>
    command(() => editor.format(name, destination ? { destination } : undefined, expected)),
  focus: (expected: number) => command(() => editor.focus(expected)),
  // Native responder resignation does not clear WebKit's retained DOM text focus.
  blur: (expected: number) => command(() => editor.blur(expected)),
  find: (text: string, expected: number) => command(() => editor.find(text, expected)),
  replace: (search: string, replacement: string, expected: number) =>
    command(() => editor.replace(search, replacement, expected)),
  replaceAll: (search: string, replacement: string, expected: number) =>
    command(() => editor.replaceAll(search, replacement, expected)),
  setEditingMode: (mode: 'source' | 'formatted', expected: number) =>
    command(() => editor.setEditingMode(mode, expected)),
  undo: (expected: number) => command(() => editor.undo(expected)),
  redo: (expected: number) => command(() => editor.redo(expected)),
  async printable(expected: number) {
    try {
      const output = await editor.printableSnapshot(expected)
      return {
        documentId: output.documentId,
        generation: output.generation,
        revision: output.revision,
        html: output.html,
        warnings: output.warnings,
      }
    } catch (error) {
      if (error instanceof InkKitError) return { snapshotError: error.code, message: error.message }
      throw error
    }
  },
  insertPaths: (paths: string[], x: number, y: number, expected: number) =>
    command(() => editor.insertPaths(paths, { clientX: x, clientY: y }, expected)),
  insertImages: (images: ImageInsertion[], x: number | null, y: number | null, expected: number) =>
    command(() =>
      editor.insertImages(
        images,
        x != null && y != null ? { clientX: x, clientY: y } : undefined,
        expected,
      ),
    ),
  pasteAsPlainText: (text: string, expected = generation) =>
    command(() => editor.pasteAsPlainText(text, expected)),
  table: (
    name: Parameters<InkKitEditor['table']>[0],
    options?: Parameters<InkKitEditor['table']>[1],
    expected = generation,
  ) => command(() => editor.table(name, options ?? undefined, expected)),
  pasteNative: (payload: {
    text: string
    html?: string
    generation: number
    images: { bytesBase64: string; mimeType: string; filename?: string; source?: string }[]
  }) => {
    void editor
      .paste(
        {
          text: payload.text,
          html: payload.html,
          images: payload.images.map((image) => ({
            bytes: decode(image.bytesBase64),
            mimeType: image.mimeType,
            filename: image.filename,
            source: image.source,
          })),
        },
        payload.generation,
      )
      .catch((error) =>
        post({
          type: 'editorWarning',
          message: error instanceof Error ? error.message : String(error),
        }),
      )
  },
  clipboardResponse(requestId: string, value: Record<string, string>) {
    const pending = replies.get(requestId)
    if (!pending) return
    replies.delete(requestId)
    if (value.error) pending.reject(new Error(value.error))
    else pending.resolve(value)
  },
  imageResponse(requestId: string, value: Record<string, string>) {
    const pending = replies.get(requestId)
    if (!pending) return
    replies.delete(requestId)
    if (value.error) pending.reject(new Error(value.error))
    else pending.resolve(value)
  },
  setAccent: (color: string) =>
    document.documentElement.style.setProperty('--inkkit-accent-color', color),
  setTextSize: (px: number) => document.documentElement.style.setProperty('font-size', `${px}px`),
  setKeymap: editor.setKeymap.bind(editor),
}
Object.assign(window, { editor: facade })
window.addEventListener('error', (event) => post({ type: 'error', message: event.message }))
window.addEventListener('unhandledrejection', (event) =>
  post({ type: 'error', message: String(event.reason) }),
)
post({ type: 'ready' })
