# Offline editor bridge

The app bootstrap consumes `@aicayzer/inkkit` and bundles its JavaScript and CSS into one offline HTML file. The native app owns document identity, generation, storage, appearance, and keyboard bindings. InkKit owns editing, preservation, tables, and clipboard conversion.

## Documents and snapshots

`load(text, generation, documentId)` and `reload(text, generation, documentId)` pass Markdown documents to InkKit. `snapshot(expectedGeneration)` returns complete current source with `documentId`, `generation`, `revision`, `format`, and `dirty`. Unchanged text is a successful snapshot; readiness, composition, pending images, stale generations, and script failures throw. Native save, export, close, switching, and termination must stop when retrieval fails.

`changed` carries Markdown, generation, and a monotonically increasing host sequence. Discard reports belonging to previous documents. Appearance and formatting changes do not reload source.

Expected InkKit snapshot rejections return `snapshotError` and `message` to native code, which throws a typed retrieval error. This keeps a save or copy attempted during composition or an image import from becoming a global script failure; a later snapshot can succeed after the operation finishes. Genuine script failures still block snapshot-dependent actions.

Recovery uses `rebind(expectedGeneration, nextGeneration, expectedDocumentId, documentId)` to snapshot and reload the latest source with its new identity in one JavaScript operation, retaining the caret. A preflight snapshot rejection reports that no document replacement occurred, so native code can retain the previous scope. Unknown script or response failures leave the bridge failed; snapshots throw and change callbacks cannot schedule writes until a successful load establishes a usable scope.

External storage refresh uses `refresh(expectedGeneration, nextGeneration, expectedDocumentId, documentId, expectedSource, text)`. It compares the live source and conditionally reloads in one JavaScript operation. A changed source returns `applied: false` with the live text and retains its scope. An unchanged source returns `applied: true` in the new scope. Native code buffers change messages during this operation and uses the returned sequence to discard earlier prefixes while retaining later typing. Recoverable preflight rejection restores the previous scope and delivers buffered edits; unknown failures leave the bridge failed.

## Clipboard and images

Ordinary copy exports readable text and semantic HTML. `clipboard()` asynchronously captures all content; await it before replacing the pasteboard. Copy as Markdown uses a fresh snapshot. `pasteAsPlainText(text)` inserts literal text.

Memos adapters request captured bytes through `imageRequest` and settle them through `imageResponse`; requests carry identity and generation. Native import owns storage and returns an opaque reference. The adapter must retain captured bytes until paste finishes and while the document or stored notes reference them; never sweep an import between saving its bytes and inserting its reference. Export returns base64 bytes and MIME type. InkKit preserves insertion positions and rejects late results. `writeClipboard` provides captured text, HTML, and portable image bytes. Memos writes one rich pasteboard item with ordered RTFD attachments and acknowledges success through `clipboardResponse`; image cut awaits this acknowledgement before deleting text. PadPad disables image management and preserves image syntax literally.

Native paste prefers supplied semantic HTML. When RTFD supplies the same number of ordered attachments as HTML image elements, it replaces only their transport URLs with captured image bytes, retaining alt text, titles, and surrounding content. RTF(D)-only paste imports Cocoa's styled body without its generated document headers. TIFF attachments are converted to PNG before storage. A document change during capture consumes the stale paste with a warning instead of replaying it into the new memo. Native clipboard-write failure restores the previous available representations.

## Verification

The manifest pins the published registry release `@aicayzer/inkkit@0.0.1`. Use `pnpm install --frozen-lockfile`, then run `pnpm format:check`, `pnpm typecheck`, `pnpm test`, and `pnpm build`. The lockfile records the registry archive's integrity. The resulting single HTML file includes the editor code and styles for offline use.

Consumer tests validate source preservation, stale snapshots, clipboard text and HTML, tables, and literal paste through the published package. Engine regression suites belong in InkKit. Native tests additionally exercise snapshot failures, external reloads, late image imports, and ordered RTFD attachments. Run native and interactive checks on an isolated development machine before release.

The production `LibraryStore` deliberately retains image files rather than sweeping them from one process’s view. This protects pending imports, unsaved notes in other processes, and conversion snapshots.
