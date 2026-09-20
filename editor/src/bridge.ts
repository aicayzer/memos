import type { CaretState } from './editor'

export type EditorMessage =
  | { type: 'ready' }
  | { type: 'changed'; markdown: string; generation: number }
  | ({ type: 'state' } & CaretState)
  | { type: 'openLink'; href: string }
  | { type: 'copy'; text: string }

declare global {
  interface Window {
    webkit?: { messageHandlers?: { host?: { postMessage(message: EditorMessage): void } } }
  }
}

export function postToHost(message: EditorMessage): void {
  const host = window.webkit?.messageHandlers?.host
  if (host) host.postMessage(message)
  else console.debug('host', message)
}
