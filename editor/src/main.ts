import { postToHost } from './bridge'
import { MemoEditor, type FormatCommand, type InsertedImage, type Keymap } from './editor'
import './style.css'
import { SourceFallback } from './source-fallback'

declare global {
  interface Window {
    editor: {
      load(markdown: string, generation: number): void
      reload(markdown: string, generation: number): void
      markdown(): string | null
      format(command: FormatCommand, arg?: string | number): void
      focus(): void
      insertPaths(paths: string[], x: number, y: number): void
      insertImages(images: InsertedImage[], x: number | null, y: number | null): void
      setAccent(color: string): void
      setTextSize(px: number): void
      setKeymap(keymap: Keymap): void
    }
  }
}

const root = document.getElementById('editor')
if (!root) throw new Error('editor root missing')

const formattedRoot = document.createElement('div')
root.append(formattedRoot)
const formatted = await MemoEditor.mount(formattedRoot, {
  changed(markdown, generation) {
    postToHost({ type: 'changed', markdown, generation })
  },
  stateChanged(state) {
    postToHost({ type: 'state', ...state })
  },
  openLink(href) {
    postToHost({ type: 'openLink', href })
  },
  copy(text) {
    postToHost({ type: 'copy', text })
  },
  pasteImage() {
    postToHost({ type: 'pasteImage' })
  },
})

const editor = new SourceFallback(formatted, formattedRoot, root, (markdown, generation) => {
  postToHost({ type: 'changed', markdown, generation })
})

// Links open on ⌘-click, so the pointer says so only while ⌘ is down.
for (const name of ['keydown', 'keyup'] as const) {
  window.addEventListener(name, (event) =>
    document.documentElement.classList.toggle('meta', event.metaKey),
  )
}
window.addEventListener('blur', () => document.documentElement.classList.remove('meta'))

window.editor = {
  load: (markdown, generation) => editor.load(markdown, generation),
  reload: (markdown, generation) => editor.reload(markdown, generation),
  markdown: () => editor.markdown(),
  format: (command, arg) => editor.format(command, arg),
  focus: () => editor.focus(),
  insertPaths: (paths, x, y) => editor.insertPaths(paths, x, y),
  insertImages: (images, x, y) => editor.insertImages(images, x, y),
  setAccent: (color) => document.documentElement.style.setProperty('--accent', color),
  setTextSize: (px) => document.documentElement.style.setProperty('font-size', `${px}px`),
  setKeymap: (keymap) => editor.setKeymap(keymap),
}

postToHost({ type: 'ready' })
