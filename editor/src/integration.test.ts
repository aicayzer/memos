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
      openLink() {},
      copy() {},
    })
  })
  afterEach(async () => {
    await editor?.destroy()
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
    const clipboard = await editor.clipboardSnapshot('document')
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
    expect((await editor.clipboardSnapshot('document')).html).toContain('<table')
  })

  it('keeps TXT literal while Markdown plain paste inserts literal markers', () => {
    const text = '**literal**\r\n'
    editor.loadDocument({ documentId: 'text', generation: 1, format: 'txt', text })
    expect(editor.snapshot().text).toBe(text)
    editor.loadDocument({ documentId: 'markdown', generation: 2, format: 'md', text: '' })
    editor.pasteAsPlainText('**literal**')
    expect(editor.snapshot().text).toContain('\\*\\*literal\\*\\*')
  })
  it('shares exact source, replacement and history across mode changes and reloads', () => {
    const text = '__Bold__\r\n\r\n<!-- hidden -->\r\n\r\nOdd [[target|label]]\r\n'
    editor.loadDocument({ documentId: 'switch', generation: 7, format: 'md', text })
    expect(editor.setEditingMode('source', 7)).toBe(true)
    expect(editor.snapshot(7).text).toBe(text)
    expect(editor.replace('hidden', '$& literal', 7)).toBe(true)
    expect(editor.snapshot(7).text).toContain('<!-- $& literal -->')
    editor.setEditingMode('formatted', 7)
    expect(editor.undo(7)).toBe(true)
    expect(editor.snapshot(7).text).toBe(text)
    expect(editor.redo(7)).toBe(true)
    editor.reloadDocument({ documentId: 'switch', generation: 8, format: 'md', text })
    expect(() => editor.replaceAll('Odd', 'Changed', 7)).toThrow()
    expect(editor.snapshot(8).text).toBe(text)
    editor.loadDocument({ documentId: 'next', generation: 9, format: 'md', text: 'Next' })
    expect(editor.commandState(9).commands.undo).toBe(false)
  })

  it('reports applicable command availability and exports the complete print document', async () => {
    editor.loadDocument({
      documentId: 'print',
      generation: 1,
      format: 'md',
      text: '# Title\n\n**Body**\n\n<!-- private -->',
    })
    editor.setEditingMode('source', 1)
    expect(editor.commandState(1).commands.format.bold).toBe(false)
    const printable = await editor.printableSnapshot(1)
    expect(printable).toMatchObject({ documentId: 'print', generation: 1 })
    expect(printable.html).toContain('<strong>Body</strong>')
    expect(printable.html).not.toContain('private')
    await expect(editor.printableSnapshot(0)).rejects.toThrow()
    expect(editor.snapshot(1).text).toContain('<!-- private -->')
  })
})
