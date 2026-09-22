import { imageSchema } from '@milkdown/kit/preset/commonmark'
import type { Node as ProseNode } from '@milkdown/kit/prose/model'
import type { EditorView, NodeView } from '@milkdown/kit/prose/view'
import { $view } from '@milkdown/kit/utils'

/** The folder a memo's own images sit in, beside the store file, and what the app serves them under. */
const folder = 'images'
const scheme = 'memo-image'

/** An image this memo owns, as against one somewhere on the web. */
export function isOwn(src: string): boolean {
  return src.startsWith(`${folder}/`)
}

/** The page never reads the disk: an image arrives through the app, on a scheme of its own. */
export function assetURL(src: string): string {
  return `${scheme}://memo/${src}`
}

/** A width rides in the alt text, as `![a picture|400](images/….png)`. Anything else reading the memo
 *  shows the picture and keeps the number, which is what a plain markdown file has to do. */
export function splitAlt(alt: string): { alt: string; width: number | null } {
  const match = /^([\s\S]*)\|(\d{1,5})$/.exec(alt)
  if (!match) return { alt, width: null }
  return { alt: match[1] ?? '', width: Number(match[2]) }
}

export function joinAlt(alt: string, width: unknown): string {
  return typeof width === 'number' ? `${alt}|${width}` : alt
}

export const imageWithWidth = imageSchema.extendSchema((prev) => (ctx) => {
  const base = prev(ctx)
  return {
    ...base,
    attrs: { ...base.attrs, width: { default: null } },
    parseMarkdown: {
      match: base.parseMarkdown.match,
      runner: (state, node, type) => {
        const { alt, width } = splitAlt(String(node.alt ?? ''))
        state.addNode(type, { src: String(node.url ?? ''), alt, title: node.title ?? '', width })
      },
    },
    toMarkdown: {
      match: base.toMarkdown.match,
      runner: (state, node) => {
        state.addNode('image', undefined, undefined, {
          title: node.attrs.title,
          url: node.attrs.src,
          alt: joinAlt(node.attrs.alt, node.attrs.width),
        })
      },
    },
  }
})

const minimumWidth = 48

/** Draws the image and the handle that sizes it. A width is set in pixels and capped to the memo, so a
 *  narrow window shows the whole picture without changing what the memo says. */
class ImageView implements NodeView {
  dom: HTMLElement
  private image?: HTMLImageElement
  private width: number | null = null

  constructor(
    private node: ProseNode,
    private readonly view: EditorView,
    private readonly getPos: () => number | undefined,
  ) {
    this.dom = document.createElement('span')
    this.dom.className = 'image'
    this.render()
  }

  update(node: ProseNode): boolean {
    if (node.type !== this.node.type) return false
    this.node = node
    this.render()
    return true
  }

  /// The handle's own events are the view's business, not the document's.
  stopEvent(event: Event): boolean {
    return event.target instanceof HTMLElement && event.target.classList.contains('image-handle')
  }

  ignoreMutation(): boolean {
    return true
  }

  private render(): void {
    const { src, alt, title, width } = this.node.attrs
    this.dom.textContent = ''
    this.width = typeof width === 'number' ? width : null
    // An image from the web is never fetched; the memo shows what it was called instead.
    if (!isOwn(String(src))) {
      this.dom.classList.add('image-absent')
      this.dom.textContent = String(alt || src)
      return
    }
    this.dom.classList.remove('image-absent')
    const image = document.createElement('img')
    image.src = assetURL(String(src))
    image.alt = String(alt ?? '')
    if (title) image.title = String(title)
    if (this.width != null) image.style.width = `${this.width}px`
    this.image = image
    const handle = document.createElement('span')
    handle.className = 'image-handle'
    handle.addEventListener('pointerdown', this.startResize)
    this.dom.append(image, handle)
  }

  private startResize = (event: PointerEvent): void => {
    const image = this.image
    if (!image) return
    event.preventDefault()
    const handle = event.currentTarget as HTMLElement
    const startX = event.clientX
    const startWidth = image.getBoundingClientRect().width
    const limit = this.view.dom.clientWidth
    handle.setPointerCapture(event.pointerId)
    const move = (moved: PointerEvent) => {
      const next = Math.round(
        Math.min(limit, Math.max(minimumWidth, startWidth + (moved.clientX - startX))),
      )
      this.width = next
      image.style.width = `${next}px`
    }
    const done = () => {
      handle.removeEventListener('pointermove', move)
      handle.removeEventListener('pointerup', done)
      handle.removeEventListener('pointercancel', done)
      this.commit()
    }
    handle.addEventListener('pointermove', move)
    handle.addEventListener('pointerup', done)
    handle.addEventListener('pointercancel', done)
  }

  private commit(): void {
    const pos = this.getPos()
    if (pos == null || this.width === this.node.attrs.width) return
    const { state } = this.view
    this.view.dispatch(
      state.tr.setNodeMarkup(pos, undefined, { ...this.node.attrs, width: this.width }),
    )
  }
}

export const imageView = $view(
  imageWithWidth.node,
  () => (node, view, getPos) => new ImageView(node, view, getPos),
)
