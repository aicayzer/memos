import { InkKitError, type InkKitEditor } from '@aicayzer/inkkit'

const reasons = new Set([
  'matching-budget',
  'source-location',
  'reopen-mismatch',
  'parse-refusal',
  'unexpected',
])

export function userMessage(code: string): string {
  switch (code) {
    case 'composition':
      return 'Finish entering text before trying again.'
    case 'operation-pending':
      return 'An image is still being added. Try again in a moment.'
    case 'not-ready':
      return 'The editor is still loading. Try again in a moment.'
    case 'stale-document':
      return 'Your memo changed. Try again.'
    case 'preservation':
      return 'That edit couldn’t be applied. Your previous text is unchanged.'
    default:
      return 'The editor couldn’t complete that action. Your text is still open.'
  }
}

export function errorFields(
  error: unknown,
  generation: number,
  editor: InkKitEditor | undefined,
  recording: boolean,
) {
  const code = error instanceof InkKitError ? error.code : 'internal'
  const fields: {
    code: string
    message: string
    generation: number
    revision?: number
    reason?: string
  } = {
    code,
    message: userMessage(code),
    generation,
  }
  if (editor) {
    try {
      const report = editor.diagnosticReport()
      fields.revision = report.state.revision
      const reason = recording
        ? (report.events.length ? report.events : report.incident?.events)
            ?.slice()
            .reverse()
            .find((event) => event.code === code && event.reason)?.reason
        : undefined
      if (reason && reasons.has(reason)) fields.reason = reason
    } catch {
      /* A report failure must not replace the original refusal. */
    }
  }
  return fields
}
