import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { InkKitEditor } from '@aicayzer/inkkit'

describe('packed editor consumer', () => {
  let root: HTMLDivElement
  let editor: InkKitEditor
  beforeEach(async () => {
    root = document.createElement('div')
    document.body.append(root)
    editor = await InkKitEditor.mount(root, {
      changed() {},
      stateChanged() {},
      openLink() {},
      copy() {},
    })
  })
  afterEach(async () => {
    await editor.destroy()
    root.remove()
  })

  it('keeps loaded source and rejects stale document snapshots', () => {
    const text = '\uFEFF---\r\ntitle: Draft\r\n---\r\n\r\n__bold__\r\n\r\nTail\r\n'
    editor.loadDocument({ documentId: 'fixture', generation: 1, format: 'md', text })
    expect(editor.snapshot(1)).toMatchObject({
      text,
      dirty: false,
      documentId: 'fixture',
      generation: 1,
    })
    expect(() => editor.snapshot(0)).toThrow()
  })

  it('exports formatted content as readable text and semantic HTML', async () => {
    editor.loadDocument({
      documentId: 'clipboard',
      generation: 1,
      format: 'md',
      text: 'tight. and **bold** \n',
    })
    const clipboard = await editor.clipboardSnapshot(true)
    expect(clipboard.text).toContain('tight. and bold')
    expect(clipboard.text).not.toContain('&#x20;')
    expect(clipboard.text).not.toContain('**')
    expect(clipboard.html).toContain('<strong>bold</strong>')
  })

  it('imports an editable HTML table without concatenating its cells', async () => {
    editor.loadDocument({ documentId: 'table', generation: 1, format: 'md', text: '' })
    await editor.paste({
      text: 'Name\tValue\nAlice\t42',
      html: '<table><tr><th>Name</th><th>Value</th></tr><tr><td>Alice</td><td>42</td></tr></table>',
    })
    expect(editor.snapshot().text).toMatch(/\|\s*Alice\s*\|\s*42\s*\|/)
    expect((await editor.clipboardSnapshot(true)).html).toContain('<table')
  })

  it('keeps TXT literal while Markdown plain paste inserts literal markers', () => {
    const text = '**literal**\r\n'
    editor.loadDocument({ documentId: 'text', generation: 1, format: 'txt', text })
    expect(editor.snapshot().text).toBe(text)
    editor.loadDocument({ documentId: 'markdown', generation: 2, format: 'md', text: '' })
    editor.pasteAsPlainText('**literal**')
    expect(editor.snapshot().text).toContain('\\*\\*literal\\*\\*')
  })
})
