// jsdom lays nothing out; ProseMirror's scrollIntoView still asks.
const none = () => [] as unknown as DOMRectList
const zero = () => new DOMRect(0, 0, 0, 0)
Element.prototype.getClientRects ??= none
Range.prototype.getClientRects ??= none
Range.prototype.getBoundingClientRect ??= zero
// Nor does it hit-test; a drop point then resolves to the caret.
document.elementFromPoint ??= () => null
// The editor runs in a macOS web view, so Mod means Meta; jsdom reports no platform.
Object.defineProperty(navigator, 'platform', { value: 'MacIntel', configurable: true })
// Nor does it paint highlights; plain sets in a map let a test read what would be painted.
globalThis.Highlight ??= class extends Set<AbstractRange> {} as unknown as typeof Highlight
globalThis.CSS ??= {} as typeof CSS
if (!('highlights' in CSS))
  Object.defineProperty(CSS, 'highlights', { value: new Map<string, Highlight>() })
