// jsdom lays nothing out; ProseMirror's scrollIntoView still asks.
const none = () => [] as unknown as DOMRectList
const zero = () => new DOMRect(0, 0, 0, 0)
Element.prototype.getClientRects ??= none
Range.prototype.getClientRects ??= none
Range.prototype.getBoundingClientRect ??= zero
