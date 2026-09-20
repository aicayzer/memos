import { editorViewCtx, serializerCtx } from '@milkdown/kit/core'
import type { Ctx, MilkdownPlugin } from '@milkdown/kit/ctx'
import type { Node as ProseNode } from '@milkdown/kit/prose/model'
import { commonmark, remarkPreserveEmptyLinePlugin } from '@milkdown/kit/preset/commonmark'
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

// Without it an empty paragraph is written as `<br />`, which the dialect forbids.
const commonmarkWithoutEmptyLines = commonmark.filter(
  (plugin) => !(remarkPreserveEmptyLinePlugin as MilkdownPlugin[]).includes(plugin),
)

export const dialect: MilkdownPlugin[] = [
  commonmarkWithoutEmptyLines,
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

// Empty paragraphs are spacing, not content, so they are left out of the markdown.
function withoutEmptyParagraphs(doc: ProseNode): ProseNode {
  const blocks: ProseNode[] = []
  doc.forEach((block) => {
    if (block.type.name !== 'paragraph' || block.content.size > 0) blocks.push(block)
  })
  if (blocks.length === doc.childCount) return doc
  return doc.type.create(doc.attrs, blocks.length > 0 ? blocks : [doc.child(0)])
}

export function serialize(ctx: Ctx, doc: ProseNode = ctx.get(editorViewCtx).state.doc): string {
  return ctx.get(serializerCtx)(withoutEmptyParagraphs(doc))
}
