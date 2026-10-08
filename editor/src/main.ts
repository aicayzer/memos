import {
  InkKitEditor,
  InkKitError,
  type CapturedImage,
  type ClipboardOutput,
  type DocumentContext,
  type ImageAdapter,
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
  const scope = editor.snapshot()
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
      documentId: scope.documentId,
      generation: scope.generation,
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
    changed(markdown, generation) {
      post({ type: 'changed', markdown, generation })
    },
    stateChanged(state) {
      post({ type: 'state', ...state, generation })
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
const facade = {
  load(text: string, nextGeneration: number, documentId = String(nextGeneration)) {
    generation = nextGeneration
    editor.loadDocument({ text, generation, documentId, format: 'md' })
  },
  reload(text: string, nextGeneration: number, documentId = String(nextGeneration)) {
    generation = nextGeneration
    editor.reloadDocument({ text, generation, documentId, format: 'md' })
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
  snapshot(expectedGeneration: number) {
    try {
      return editor.snapshot(expectedGeneration)
    } catch (error) {
      // An expected rejection must not reach WKWebView's global script-error listener.
      if (error instanceof InkKitError) return { snapshotError: error.code, message: error.message }
      throw error
    }
  },
  clipboard: () => editor.clipboardSnapshot(true),
  format: editor.format.bind(editor),
  focus: editor.focus.bind(editor),
  find: editor.find.bind(editor),
  insertText: editor.insertText.bind(editor),
  keyDown: editor.keyDown.bind(editor),
  insertPaths: editor.insertPaths.bind(editor),
  insertImages: (
    values: { path?: string; src?: string; alt: string }[],
    x: number | null,
    y: number | null,
  ) =>
    editor.insertImages(
      values.map((value) => ({ path: value.path ?? value.src ?? '', alt: value.alt })),
      x ?? undefined,
      y ?? undefined,
    ),
  pasteAsPlainText: editor.pasteAsPlainText.bind(editor),
  table: editor.table.bind(editor),
  pasteNative: (payload: {
    text: string
    html?: string
    generation: number
    images: { bytesBase64: string; mimeType: string; filename?: string; source?: string }[]
  }) => {
    if (payload.generation !== generation) throw new Error('The memo changed')
    void editor
      .paste({
        text: payload.text,
        html: payload.html,
        images: payload.images.map((image) => ({
          bytes: decode(image.bytesBase64),
          mimeType: image.mimeType,
          filename: image.filename,
          source: image.source,
        })),
      })
      .catch((error) => post({ type: 'editorWarning', message: String(error) }))
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
  setAccent: (color: string) => document.documentElement.style.setProperty('--accent', color),
  setTextSize: (px: number) => document.documentElement.style.setProperty('font-size', `${px}px`),
  setReadingWidth: (width: number | null) => {
    if (width !== null && Number.isFinite(width) && width > 0)
      document.documentElement.style.setProperty('--reading-width', `${width}px`)
    else document.documentElement.style.removeProperty('--reading-width')
  },
  setKeymap: editor.setKeymap.bind(editor),
}
Object.assign(window, { editor: facade })
for (const name of ['keydown', 'keyup'] as const)
  window.addEventListener(name, (event) =>
    document.documentElement.classList.toggle('meta', event.metaKey),
  )
window.addEventListener('blur', () => document.documentElement.classList.remove('meta'))
window.addEventListener('error', (event) => post({ type: 'error', message: event.message }))
window.addEventListener('unhandledrejection', (event) =>
  post({ type: 'error', message: String(event.reason) }),
)
post({ type: 'ready' })
