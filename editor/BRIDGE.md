# Offline editor bridge

The app bootstrap consumes `@aicayzer/inkkit` and bundles its JavaScript and CSS into one offline HTML file. The native app owns document identity, generation, storage, appearance, and keyboard bindings. InkKit owns editing, preservation, tables, and clipboard conversion.

## Documents and snapshots

`load(text, generation, documentId)` and `reload(text, generation, documentId)` pass Markdown documents to InkKit. `snapshot(expectedGeneration)` returns complete current source with `documentId`, `generation`, `revision`, `format`, and `dirty`. Unchanged text is a successful snapshot; readiness, composition, pending images, stale generations, and script failures throw. Native save, export, close, switching, and termination must stop when retrieval fails.

`blur(expectedGeneration)` releases focus only from the editor’s text surface in the current generation, because native responder resignation does not clear WebKit’s retained DOM focus. Native reading selection submits this before resigning the editor’s responder. It leaves embedded controls and other responders focused; subsequent explicit focus remains ordered after it. `focus(expectedGeneration)` is scoped the same way.

`changed` carries the snapshot’s Markdown and generation, and a monotonically increasing host sequence, which keeps rising across reloads where InkKit’s revision restarts. Discard reports belonging to previous documents. Appearance and formatting changes do not reload source.

Expected InkKit snapshot rejections return `snapshotError` and `message` to native code, which throws a typed retrieval error. This keeps a save or copy attempted during composition or an image import from becoming a global script failure; a later snapshot can succeed after the operation finishes. Genuine script failures still block snapshot-dependent actions.

Recovery uses `rebind(expectedGeneration, nextGeneration, expectedDocumentId, documentId)` to snapshot and reload the latest source with its new identity in one JavaScript operation, retaining the caret. A preflight snapshot rejection reports that no document replacement occurred, so native code can retain the previous scope. Unknown script or response failures leave the bridge failed; snapshots throw and change callbacks cannot schedule writes until a successful load establishes a usable scope.

External storage refresh uses `refresh(expectedGeneration, nextGeneration, expectedDocumentId, documentId, expectedSource, text)`. It compares the live source and conditionally reloads in one JavaScript operation. A changed source returns `applied: false` with the live text and retains its scope. An unchanged source returns `applied: true` in the new scope. Native code buffers change messages during this operation and uses the returned sequence to discard earlier prefixes while retaining later typing. Recoverable preflight rejection restores the previous scope and delivers buffered edits; unknown failures leave the bridge failed.

## Clipboard and images

Ordinary copy exports readable text and semantic HTML. `clipboard()` asynchronously captures all content; await it before replacing the pasteboard. Copy as Markdown uses a fresh snapshot. `pasteAsPlainText(text, expectedGeneration)` inserts literal text in the expected document.

Dropped images reach `insertImages` as stored references with the drop point, and other dropped files reach `insertPaths`; both name the memo’s generation. Memos adapters request captured bytes through `imageRequest` and settle them through `imageResponse`; requests carry identity and generation. Native import owns storage and returns an opaque reference. The adapter must retain captured bytes until paste finishes and while the document or stored notes reference them; never sweep an import between saving its bytes and inserting its reference. Export returns base64 bytes and MIME type. InkKit preserves insertion positions and rejects late results. `writeClipboard` provides captured text, HTML, and portable image bytes. Memos writes one rich pasteboard item with ordered RTFD attachments and acknowledges success through `clipboardResponse`; image cut awaits this acknowledgement before deleting text.

Native paste prefers supplied semantic HTML. When RTFD supplies the same number of ordered attachments as HTML image elements, it replaces only their transport URLs with captured image bytes, retaining alt text, titles, and surrounding content. RTF(D)-only paste imports Cocoa's styled body without its generated document headers. TIFF attachments are converted to PNG before storage. A document change during capture consumes the stale paste with a warning instead of replaying it into the new memo. Native clipboard-write failure restores the previous available representations.

Keyboard and menu paste target the native first responder. The web view handles paste only when it or its descendants own the keyboard in the key window. Paste as Plain Text uses the native text responder when a search or settings field owns focus. Queued editor pastes recheck the originating window, responder, and document before delivery. Accepted image pastes retain their captured insertion position and document scope while imports finish.

## Verification

The manifest pins an exact published InkKit registry release. Use `pnpm install --frozen-lockfile`, then run `pnpm format:check`, `pnpm typecheck`, `pnpm test`, and `pnpm build`. The lockfile records the registry archive's integrity. The resulting single HTML file includes the editor code and styles for offline use.

Consumer tests validate source preservation, stale snapshots, clipboard text and HTML, tables, and literal paste through the published package. Engine regression suites belong in InkKit. Native tests additionally exercise snapshot failures, external reloads, late image imports, and ordered RTFD attachments. Run native and interactive checks on an isolated development machine before release.

The production `LibraryStore` deliberately retains image files rather than sweeping them from one process’s view. This protects pending imports, unsaved notes in other processes, and conversion snapshots.

## Editing commands and printing

`commandState` messages carry `documentId`, `generation`, editing `mode`, `caret`, and the public `commands` maps, and are the only source of caret state. Ignore messages for another scope. Menu availability follows these maps, where headings are the `heading1` to `heading6` entries of `commands.format`; source mode shares the same document and undo history.

`format(command, destination, generation)`, `find(text, generation)`, `replace(search, replacement, generation)`, `replaceAll(search, replacement, generation)`, `setEditingMode(mode, generation)`, `undo(generation)`, `redo(generation)`, `table`, `pasteAsPlainText`, `insertImages` and `insertPaths` call the public facade. Search and replacement are literal. Reload retains mode; loading another memo resets history.

InkKit throws from a facade call that it refuses, and sends nothing to its error event. The bridge returns `commandError` and `message` instead, and native code shows that message through the same warning path as any other refused edit. Edits the person makes, such as typing or a shortcut, arrive as `editorWarning` through InkKit's error event. `pasteNative` has no reply to carry a refusal, so the page posts its rejection as `editorWarning` itself, as it does for a copy whose images were unavailable.

`printable(generation)` awaits `printableSnapshot` and returns scoped `html`, `revision` and `warnings`, or `snapshotError` and `message`. HTML is a complete frozen portable document, with images embedded. Native printing awaits a fresh source snapshot, validates the print scope, loads HTML in a separate retained web view, waits for fonts and image decoding, then rechecks the live revision before presenting the standard Print panel with its PDF option. Failures do not print partial content or alter the memo.
