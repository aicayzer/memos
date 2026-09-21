import { linkSchema } from '@milkdown/kit/preset/commonmark'
import { InputRule } from '@milkdown/kit/prose/inputrules'
import { $inputRule } from '@milkdown/kit/utils'

// A typed URL becomes a link once a space follows it; nothing links it otherwise.
export const autolinkInputRule = $inputRule((ctx) => {
  return new InputRule(
    /(?:^|\s)(https?:\/\/[^\s<>]+[^\s<>.,;:!?)\]])\s$/,
    (state, match, _start, end) => {
      const url = match[1]
      if (!url) return null
      const to = end
      const from = to - url.length
      const mark = linkSchema.type(ctx).create({ href: url })
      return state.tr.addMark(from, to, mark).insertText(' ', end, end).removeStoredMark(mark)
    },
  )
})
