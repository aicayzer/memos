import { postToHost } from './bridge'
import { MemoEditor, type FormatCommand } from './editor'
import './style.css'

declare global {
  interface Window {
    editor: {
      load(markdown: string): void
      markdown(): string
      format(command: FormatCommand, arg?: string | number): void
      focus(): void
      setAccent(color: string): void
    }
  }
}

const root = document.getElementById('editor')
if (!root) throw new Error('editor root missing')

let pending: number | undefined
let latest = ''

const editor = await MemoEditor.mount(root, {
  changed(markdown) {
    latest = markdown
    window.clearTimeout(pending)
    pending = window.setTimeout(() => postToHost({ type: 'changed', markdown: latest }), 150)
  },
  stateChanged(state) {
    postToHost({ type: 'state', ...state })
  },
  openLink(href) {
    postToHost({ type: 'openLink', href })
  },
})

window.editor = {
  load: (markdown) => {
    window.clearTimeout(pending)
    editor.load(markdown)
  },
  markdown: () => editor.markdown(),
  format: (command, arg) => editor.format(command, arg),
  focus: () => editor.focus(),
  setAccent: (color) => document.documentElement.style.setProperty('--accent', color),
}

postToHost({ type: 'ready' })
