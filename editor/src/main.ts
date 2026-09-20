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

const editor = await MemoEditor.mount(root, {
  changed(markdown) {
    postToHost({ type: 'changed', markdown })
  },
  stateChanged(state) {
    postToHost({ type: 'state', ...state })
  },
  openLink(href) {
    postToHost({ type: 'openLink', href })
  },
})

window.editor = {
  load: (markdown) => editor.load(markdown),
  markdown: () => editor.markdown(),
  format: (command, arg) => editor.format(command, arg),
  focus: () => editor.focus(),
  setAccent: (color) => document.documentElement.style.setProperty('--accent', color),
}

postToHost({ type: 'ready' })
