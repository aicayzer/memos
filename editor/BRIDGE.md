# Offline editor bridge

The app bootstrap consumes `@aicayzer/inkkit` and bundles its JavaScript and CSS into one offline HTML file. The native app owns document identity, generation, storage, appearance, and keyboard bindings. InkKit owns editing, preservation, tables, and clipboard conversion.

## Documents and snapshots

`load(text, generation, documentId)` and `reload(text, generation, documentId)` pass Markdown documents to InkKit. `snapshot(expectedGeneration)` returns complete current source with `documentId`, `generation`, `revision`, `format`, and `dirty`. Unchanged text is a successful snapshot; readiness, composition, pending images, stale generations, and script failures throw. Native save, export, close, switching, and termination must stop when retrieval fails.

`changed` carries Markdown and generation. Discard reports belonging to previous documents. Appearance and formatting changes do not reload source.

## Clipboard and images

Ordinary copy exports readable text and semantic HTML. `clipboard()` asynchronously captures all content; await it before replacing the pasteboard. Copy as Markdown uses a fresh snapshot. `pasteAsPlainText(text)` inserts literal text.

Memos adapters request captured bytes through `imageRequest` and settle them through `imageResponse`; requests carry identity and generation. Native import owns storage and returns an opaque reference. The adapter must retain captured bytes until paste finishes and while the document or stored notes reference them; never sweep an import between saving its bytes and inserting its reference. Export returns base64 bytes and MIME type. InkKit preserves insertion positions and rejects late results. `writeClipboard` provides captured text, HTML, and portable image bytes. Memos writes one rich pasteboard item with ordered RTFD attachments and acknowledges success through `clipboardResponse`; image cut awaits this acknowledgement before deleting text. PadPad disables image management and preserves image syntax literally.

## Verification

The manifest pins the published registry release `@aicayzer/inkkit@0.0.1`. Use `pnpm install --frozen-lockfile`, then run `pnpm format:check`, `pnpm typecheck`, `pnpm test`, and `pnpm build`. The lockfile records the registry archive's integrity. The resulting single HTML file includes the editor code and styles for offline use.

Consumer tests validate source preservation, stale snapshots, clipboard text and HTML, tables, and literal paste through the published package. Engine regression suites belong in InkKit. Native tests additionally exercise snapshot failures, external reloads, late image imports, and ordered RTFD attachments. Run native and interactive checks on an isolated development machine before release.

The production `LibraryStore` deliberately retains image files rather than sweeping them from one process’s view. This protects pending imports, unsaved notes in other processes, and conversion snapshots.
