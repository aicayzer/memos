# Offline editor bridge

The app bootstrap consumes `@aicayzer/inkkit` and bundles its JavaScript and CSS into one offline HTML file. The native app owns document identity, generation, storage, appearance, and keyboard bindings. InkKit owns editing, preservation, tables, and clipboard conversion.

## Documents and snapshots

`load(text, generation, documentId)` and `reload(text, generation, documentId)` pass Markdown documents to InkKit. `snapshot(expectedGeneration)` returns complete current source with `documentId`, `generation`, `revision`, `format`, and `dirty`. Unchanged text is a successful snapshot; readiness, composition, pending images, stale generations, and script failures throw. Native save, export, close, switching, and termination must stop when retrieval fails.

`changed` carries Markdown and generation. Discard reports belonging to previous documents. Appearance and formatting changes do not reload source.

## Clipboard and images

Ordinary copy exports readable text and semantic HTML. `clipboard()` asynchronously captures all content; await it before replacing the pasteboard. Copy as Markdown uses a fresh snapshot. `pasteAsPlainText(text)` inserts literal text.

Memos adapters request captured bytes through `imageRequest` and settle them through `imageResponse`; requests carry identity and generation. Native import owns storage and returns an opaque reference. The adapter must retain captured bytes until paste finishes and while the document or stored notes reference them; never sweep an import between saving its bytes and inserting its reference. Export returns base64 bytes and MIME type. InkKit preserves insertion positions and rejects late results. `writeClipboard` provides captured text, HTML, and portable image bytes. Memos writes one rich pasteboard item with ordered RTFD attachments and acknowledges success through `clipboardResponse`; image cut awaits this acknowledgement before deleting text. PadPad disables image management and preserves image syntax literally.

## Verification

Install the exact InkKit release tarball in this isolated integration branch, then run editor type checking, consumer tests, and the offline build. Copied engine regression suites belong in InkKit. Native tests additionally exercise snapshot failure and clipboard interoperability. Keep tarball paths out of production manifests; use the registry version after publication.

These branches prepare the integration before npm publication. The manifest names `0.0.1`; regenerate and verify the registry lockfile after that version exists. Provisional verification installs the exact tarball only in disposable copies, leaving local tarball paths out of the eventual production lockfile.

The production `LibraryStore` deliberately retains image files rather than sweeping them from one process’s view. This protects pending imports, unsaved notes in other processes, and conversion snapshots.
