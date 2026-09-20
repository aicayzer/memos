# Bridge

The app hosts the built `index.html`, copied into its `Resources/Editor/` by the app build, in a web view. The two sides talk through one message handler and one global object, both JSON.

## Editor to app

Posted with `window.webkit.messageHandlers.host.postMessage(message)`. Without a host (a browser during development) messages go to `console.debug`.

| `type`     | Fields                                             | When                                                                                                                    |
| ---------- | -------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `ready`    |                                                    | The editor is mounted and `window.editor` exists.                                                                       |
| `changed`  | `markdown: string`, `generation: number`           | The document changed by an edit, debounced by 200ms. `generation` is the value given to the `load` the edit belongs to. |
| `state`    | `marks: Mark[]`, `block: Block`, `quoted: boolean` | The caret moved or the document changed. `quoted` is true inside a quote at any depth; `block` is what sits inside it.  |
| `openLink` | `href: string`                                     | A link was ⌘-clicked. The app opens it; the page never navigates.                                                       |

`Mark` is one of `bold`, `italic`, `strikethrough`, `code`, `link`.

`Block` is `{ type: 'paragraph' }`, `{ type: 'heading', level }`, `{ type: 'codeBlock' }`, `{ type: 'bulletList' }`, `{ type: 'orderedList' }` or `{ type: 'taskList' }`.

## App to editor

Called with `evaluateJavaScript` on `window.editor`.

| Call                         | Effect                                                                                                                                                                |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `load(markdown, generation)` | Replace the document and put the caret at the start. Emits `state`, not `changed`; the loaded text's canonical form is the baseline later edits are measured against. |
| `markdown()`                 | Return the document as markdown, or `null` while it is still what was loaded.                                                                                         |
| `format(command, arg?)`      | Apply a formatting command at the selection, then focus the editor.                                                                                                   |
| `focus()`                    | Focus the editor.                                                                                                                                                     |
| `setAccent(color)`           | Set the accent color used for links, markers and the caret.                                                                                                           |

`command` is one of `heading` (with `arg` 1 to 3; the same level again turns the block back into a paragraph), `paragraph`, `bold`, `italic`, `strikethrough`, `code`, `codeBlock` (with `arg` an optional language), `quote` (lifts out of the quote when already inside one), `bulletList`, `orderedList`, `taskList`, `link` (with `arg` the URL).

## Markdown

CommonMark plus strikethrough, task lists and bare URLs. Documents are written in one canonical form: `-` bullets, `*` emphasis, `**` strong, fenced code, `---` rules, `\` hard breaks, and `<url>` for links whose text is the URL. `fixtures/dialect.md` is the canonical form of every construct, and `test/roundtrip.test.ts` holds it byte for byte.
