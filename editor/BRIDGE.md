# Bridge

The app hosts the built `index.html`, copied into its `Resources/Editor/` by the app build, in a web view. The two sides talk through one message handler and one global object, both JSON.

## Editor to app

Posted with `window.webkit.messageHandlers.host.postMessage(message)`. Without a host (a browser during development) messages go to `console.debug`.

| `type`       | Fields                                             | When                                                                                                                       |
| ------------ | -------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `ready`      |                                                    | The editor is mounted and `window.editor` exists.                                                                          |
| `changed`    | `markdown: string`, `generation: number`           | The document changed by an edit, debounced by 200ms. `generation` is the value given to the `load` the edit belongs to.    |
| `state`      | `marks: Mark[]`, `block: Block`, `quoted: boolean` | The caret or document changed. `quoted` is true when one quote holds the whole selection; `block` is what sits inside it.  |
| `openLink`   | `href: string`                                     | A link was ⌘-clicked. The app opens it; the page never navigates.                                                          |
| `copy`       | `text: string`                                     | A code block's copy button was clicked. The app puts the text on the pasteboard.                                           |
| `pasteImage` |                                                    | An image was pasted. The bytes are already on the pasteboard, which the app reads itself, and answers with `insertImages`. |
| `error`      | `message: string`                                  | An uncaught error or rejection in the page. Posted by a script the app injects, so the page needs nothing for it.          |

`Mark` is one of `bold`, `italic`, `strikethrough`, `code`, `link`.

`Block` is `{ type: 'paragraph' }`, `{ type: 'heading', level }`, `{ type: 'codeBlock' }`, `{ type: 'bulletList' }`, `{ type: 'orderedList' }` or `{ type: 'taskList' }`.

## App to editor

Called with `evaluateJavaScript` on `window.editor`.

| Call                           | Effect                                                                                                                                                                                                                           |
| ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `load(markdown, generation)`   | Replace the document and put the caret at the end. Emits `state`, not `changed`; the loaded text's canonical form is the baseline later edits are measured against.                                                              |
| `reload(markdown, generation)` | Replace the document of the memo already open, leaving the caret and the scroll where they are. For a change made to the store from outside. Emits `state`, not `changed`.                                                       |
| `markdown()`                   | Return the document as markdown, or `null` while it is still what was loaded.                                                                                                                                                    |
| `format(command, arg?)`        | Apply a formatting command at the selection, then focus the editor.                                                                                                                                                              |
| `focus()`                      | Focus the editor.                                                                                                                                                                                                                |
| `insertPaths(paths, x, y)`     | Insert the paths, one paragraph each, at the point (from the page's top left), or at the caret when the point is off the page: in place of an empty top-level block, after the top-level block otherwise. The caret follows.     |
| `insertImages(images, x, y)`   | Insert images the app has kept. Each is `{ path, alt }`, the path being `images/<hash>.<ext>`. With a point, they go in as blocks of their own where it lands, as `insertPaths` does; with `null, null`, at the caret.           |
| `setAccent(color)`             | Set the accent color used for links, markers and the caret.                                                                                                                                                                      |
| `setTextSize(px)`              | Set the memo's text size in pixels. Headings, code and list indents are in `rem`, so they scale with it.                                                                                                                         |
| `setKeymap(keymap)`            | Bind keys to formatting: `keymap` maps a shortcut name (`bold`, `heading2`, `bulletList`, …) to ProseMirror key names (`Mod-b`, `Mod-Alt-2`). Replaces the previous bindings; the presets' own formatting keys are never active. |

`command` is one of `heading` (with `arg` 1 to 3; the same level again turns the block back into a paragraph), `paragraph`, `bold`, `italic`, `strikethrough`, `code` (at a caret, what is typed next), `codeBlock` (with `arg` an optional language), `quote` (lifts out of the quote when already inside one), `bulletList`, `orderedList`, `taskList`, `link` (with `arg` the URL).

## Images

The page has no access to the disk. An image is served by the app on the `memo-image:` scheme, which the page's content security policy is the only source it allows: `images/<hash>.png` in the markdown is fetched as `memo-image://memo/images/<hash>.png`. An image whose URL is not one of the memo's own, such as one on the web, is never fetched; the memo shows its alt text instead.

A width rides in the alt text, as `![a picture|400](images/<hash>.png)`, so a reader that knows nothing of it still shows the picture. The resize handle writes the number; the picture is never wider than the memo, whatever the number says.

## Markdown

CommonMark plus strikethrough, task lists, bare URLs and images. Documents are written in one canonical form: `-` bullets, `*` emphasis, `**` strong, fenced code, `---` rules, `\` hard breaks, and the URL alone for a link whose text is that URL, where reading it back gives the same link. `fixtures/dialect.md` is the canonical form of every construct, and `test/roundtrip.test.ts` holds it byte for byte.

Files whose loaded source differs from the visual editor's canonical serialization use a source textarea. Merely loading them still returns null from `markdown()`; actual edits preserve their metadata and unsupported syntax. Canonical memos retain the formatted editor.
