import { editorViewCtx } from '@milkdown/kit/core'
import type { MilkdownPlugin } from '@milkdown/kit/ctx'
import {
  commonmark,
  paragraphSchema,
  remarkPreserveEmptyLinePlugin,
} from '@milkdown/kit/preset/commonmark'
import {
  extendListItemSchemaForTask,
  strikethroughAttr,
  strikethroughInputRule,
  strikethroughKeymap,
  strikethroughSchema,
  toggleStrikethroughCommand,
  wrapInTaskListInputRule,
} from '@milkdown/kit/preset/gfm'
import { $remark } from '@milkdown/kit/utils'
import type { Options as StringifyOptions } from 'mdast-util-to-markdown'
import {
  gfmAutolinkLiteralFromMarkdown,
  gfmAutolinkLiteralToMarkdown,
} from 'mdast-util-gfm-autolink-literal'
import {
  gfmStrikethroughFromMarkdown,
  gfmStrikethroughToMarkdown,
} from 'mdast-util-gfm-strikethrough'
import {
  gfmTaskListItemFromMarkdown,
  gfmTaskListItemToMarkdown,
} from 'mdast-util-gfm-task-list-item'
import { gfmAutolinkLiteral } from 'micromark-extension-gfm-autolink-literal'
import { gfmStrikethrough } from 'micromark-extension-gfm-strikethrough'
import { gfmTaskListItem } from 'micromark-extension-gfm-task-list-item'
import type { Processor } from 'unified'

// Tables and footnotes are deliberately left out.
function remarkDialect(this: Processor) {
  const data = this.data() as Record<string, unknown[] | undefined>
  const add = (key: string, value: unknown) => {
    const list = (data[key] ??= [])
    list.push(value)
  }
  add('micromarkExtensions', gfmStrikethrough())
  add('micromarkExtensions', gfmTaskListItem())
  add('micromarkExtensions', gfmAutolinkLiteral())
  add('fromMarkdownExtensions', gfmStrikethroughFromMarkdown())
  add('fromMarkdownExtensions', gfmTaskListItemFromMarkdown())
  add('fromMarkdownExtensions', gfmAutolinkLiteralFromMarkdown())
  add('toMarkdownExtensions', gfmStrikethroughToMarkdown())
  add('toMarkdownExtensions', gfmTaskListItemToMarkdown())
  add('toMarkdownExtensions', gfmAutolinkLiteralToMarkdown())
}

export const remarkDialectPlugin = $remark('remarkDialect', () => remarkDialect)

// Empty paragraphs are not content: they are left out of the markdown instead of
// being written as `<br />`, which the dialect forbids.
const commonmarkWithoutEmptyLines = commonmark.filter(
  (plugin) => !(remarkPreserveEmptyLinePlugin as MilkdownPlugin[]).includes(plugin),
)

const paragraphSchemaSkippingEmpty = paragraphSchema.extendSchema((prev) => (ctx) => {
  const base = prev(ctx)
  return {
    ...base,
    toMarkdown: {
      match: base.toMarkdown.match,
      runner: (state, node) => {
        // The last block stays so the document is never empty of nodes.
        const isLast = node === ctx.get(editorViewCtx).state.doc.lastChild
        if (node.content.size === 0 && !isLast) return
        base.toMarkdown.runner(state, node)
      },
    },
  }
})

export const dialect: MilkdownPlugin[] = [
  commonmarkWithoutEmptyLines,
  paragraphSchemaSkippingEmpty,
  extendListItemSchemaForTask,
  strikethroughAttr,
  strikethroughSchema,
  strikethroughInputRule,
  strikethroughKeymap,
  toggleStrikethroughCommand,
  wrapInTaskListInputRule,
  remarkDialectPlugin,
].flat()

// One output form, so a memo written back unchanged is byte-stable.
export const stringifyOptions: StringifyOptions = {
  bullet: '-',
  emphasis: '*',
  strong: '*',
  fences: true,
  listItemIndent: 'one',
  rule: '-',
}
