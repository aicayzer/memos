# Offline editor bridge

The app bootstrap consumes `@aicayzer/inkkit` and bundles its JavaScript and CSS into one offline HTML file. The native app owns document identity, generation, storage, appearance, and keyboard bindings. InkKit owns editing, preservation, tables, and clipboard conversion.

The editor build generates host dependency notices and copies Inkkit's license and notices into `dist/licenses/`. The native build includes that directory alongside the offline page and `editor-version.json`, which records the bundled package version for diagnostic reports.

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

Right-clicking an image posts `imageMenu` with the stored `reference` and the click position as `x` and `y`, in CSS pixels of the web view. The `images` adapter sets `contextMenu`, so InkKit selects the image and suppresses the web view's own menu, whose Download Image item does nothing here. Native code ignores a reference the image store did not write, shows a menu at the point with a single Save Image… item, and on choosing it reads the stored bytes before asking where to save them. The file is written atomically, and a failure shows a warning and writes nothing. The message carries no document scope because it answers a click the person is making now.

Native paste prefers supplied semantic HTML. When RTFD supplies the same number of ordered attachments as HTML image elements, it replaces only their transport URLs with captured image bytes, retaining alt text, titles, and surrounding content. RTF(D)-only paste imports Cocoa's styled body without its generated document headers. TIFF attachments are converted to PNG before storage. A document change during capture consumes the stale paste with a warning instead of replaying it into the new memo. Native clipboard-write failure restores the previous available representations.

Keyboard and menu paste target the native first responder. The web view handles paste only when it or its descendants own the keyboard in the key window. Paste as Plain Text uses the native text responder when a search or settings field owns focus. Queued editor pastes recheck the originating window, responder, and document before delivery. Accepted image pastes retain their captured insertion position and document scope while imports finish.

## Verification

The manifest pins an exact published InkKit registry release. Use `pnpm install --frozen-lockfile`, then run `pnpm format:check`, `pnpm typecheck`, `pnpm test`, and `pnpm build`. The lockfile records the registry archive's integrity. The resulting single HTML file includes the editor code and styles for offline use.

Consumer tests validate source preservation, stale snapshots, clipboard text and HTML, tables, and literal paste through the published package. Engine regression suites belong in InkKit. Native tests additionally exercise snapshot failures, external reloads, late image imports, and ordered RTFD attachments. Run native and interactive checks on an isolated development machine before release.

The production `LibraryStore` deliberately retains image files rather than sweeping them from one process’s view. This protects pending imports, unsaved notes in other processes, and conversion snapshots.

## Editing commands and printing

`commandState` messages carry `documentId`, `generation`, editing `mode`, `caret`, and the public `commands` maps, and are the only source of caret state. Ignore messages for another scope. Menu availability follows these maps, where headings are the `heading1` to `heading6` entries of `commands.format`; source mode shares the same document and undo history.

`format(command, destination, generation)`, `moveBlock(direction, generation)`, `find(text, generation)`, `replace(search, replacement, generation)`, `replaceAll(search, replacement, generation)`, `setEditingMode(mode, generation)`, `undo(generation)`, `redo(generation)`, `table`, `pasteAsPlainText`, `insertImages` and `insertPaths` call the public facade. Search and replacement are literal. Reload retains mode; loading another memo resets history.

InkKit always enables the typed table-row shortcut; it has no option for it. Block movement defaults to Option-Up and Option-Down, and its Move Up and Move Down titles and keys come from the shared shortcut definitions, as every editor shortcut's do. The Format menu follows `commands.moveBlockUp` and `commands.moveBlockDown`. InkKit's smart punctuation and the slash menu are disabled at mount. No wiki-link adapter is supplied, so `[[` stays literal.

Format menu items for editor shortcuts are disabled unless the editor owns the first responder, so their keys reach a focused native field. A queued `moveBlock` also rechecks its window, responder, and document before it runs.

InkKit throws from a facade call that it refuses, and sends nothing to its error event. The bridge returns `commandError`, `code`, `generation`, fixed user-facing `message`, and a revision and closed-category preservation reason when available. Native code shows its own user-facing copy through the warning path and ignores responses for an old document or generation. Both awaited commands and fire-and-forget calls handle coded refusals without disabling the bridge. Edits the person makes, such as typing or a shortcut, arrive as `editorWarning` through InkKit's error event. `pasteNative` has no reply to carry a refusal, so the page posts its rejection as `editorWarning` itself, as it does for a copy whose images were unavailable.

`printable(generation)` awaits `printableSnapshot` and returns scoped `html`, `revision` and `warnings`, or `snapshotError` and `message`. HTML is a complete frozen portable document, with images embedded. Native printing awaits a fresh source snapshot, validates the print scope, loads HTML in a separate retained web view, waits for fonts and image decoding, then rechecks the live revision before presenting the standard Print panel with its PDF option. Failures do not print partial content or alter the memo.

## Reading viewport and counts

The host registers the scrolling editor root with `setViewport`, with 24 CSS pixels at the top for the fade and 96 at the bottom for the formatting bar and count. InkKit uses these insets when revealing the caret and search results.

The page posts `textCounts` with `documentId`, `generation`, `characters`, and `words`. Counts come from InkKit's public `textSnapshot()`: formatted text omits Markdown delimiters and hidden comments; source mode counts the literal text it displays. Characters are Unicode grapheme clusters, including spaces and line breaks. Words use `Intl.Segmenter` word boundaries. The native controller rejects counts for another memo or generation. Composition and pending imports retain the last valid count until the editor can report again.

Appearance settings can hide the count. The count also hides while the formatting bar is open. The bottom-center count toggles between characters and words, and the selected unit is remembered.

## Local diagnostics

General Settings contains **Record diagnostic activity**, off by default and persisted in preferences, and **Copy Diagnostic Report**. Recording stays on this Mac. It records bounded native operation, input, focus, snapshot, and save categories alongside Inkkit's public diagnostic report. Native history keeps 200 events and an incident with up to 40 subsequent events. The report includes the actual app version, build, bundled editor version, bounded numeric macOS version, and random session identifiers. It contains no hardware identifiers or arbitrary OS description strings. It excludes memo content and identities, filenames, paths, links, clipboard data, raw event data, and arbitrary exception messages.

`setDiagnosticsEnabled(enabled)` forwards the setting through Inkkit's public API. `diagnosticReport()` retrieves the engine report without taking a snapshot or requiring a document generation. Native collection times out after two seconds, validates the current controller and recording session, and accepts only documented enum, boolean, numeric, UUID, and restricted presentation fields. Geometry is collected only for an incident or an explicit report request. Global JavaScript failures forward only `script-error` or `unhandled-rejection` classifications.

A rejection saves one sanitized incident file, capped at 256 KiB, for the next launch. Disabling recording clears native and engine histories and deletes that file. If deletion fails, Settings shows a fixed error and a retry action. Off-state launch and reset retry deletion. Cached metadata is validated again on launch. Copying explicitly writes the report to the native clipboard; an unavailable engine report still allows the native history to be copied, and a clipboard-write failure restores the previous representations. Reports are never sent automatically. Tests inject isolated preferences and incident-file locations; resetting the recorder deletes both the test setting and retained file.
