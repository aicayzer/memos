import { type InkKitEditor, type TextRange } from '@aicayzer/inkkit'

export interface SearchState {
  documentId: string
  generation: number
  query: string
  current: number
  total: number
}

/** Native controls own presentation; the engine owns which text is searchable. */
export class MemoFind {
  private query = ''
  private lastState = ''
  private cached?: { snapshotId: string; query: string; matches: readonly TextRange[] }

  constructor(
    private readonly editor: InkKitEditor,
    private readonly report: (state: SearchState) => void,
  ) {}

  reset(expected: number): void {
    this.editor.textSnapshot(expected)
    this.query = ''
    this.refresh(expected)
  }

  restore(expected: number): void {
    const snapshot = this.editor.textSnapshot(expected)
    this.editor.find(this.query, expected)
    this.editor.selectTextRange(snapshot.selection)
    this.refresh(expected)
  }

  refresh(expected: number): void {
    const snapshot = this.editor.textSnapshot(expected)
    const matches = this.matches(this.query, expected, snapshot.snapshotId)
    const selected = matches.findIndex((range) => sameRange(range, snapshot.selection))
    const state: SearchState = {
      documentId: snapshot.documentId,
      generation: snapshot.generation,
      query: this.query,
      current: selected + 1,
      total: matches.length,
    }
    const serialized = JSON.stringify(state)
    if (serialized !== this.lastState) {
      this.lastState = serialized
      this.report(state)
    }
  }

  find(text: string, expected: number, direction = 0): boolean {
    const snapshot = this.editor.textSnapshot(expected)
    const matches = this.matches(text, expected, snapshot.snapshotId)
    const changedQuery = text !== this.query
    const selected = matches.findIndex((range) => sameRange(range, snapshot.selection))
    let index = selected
    if (changedQuery || index < 0) {
      if (direction < 0) {
        index = -1
        for (let candidate = matches.length - 1; candidate >= 0; candidate -= 1) {
          if (matches[candidate]!.to <= snapshot.selection.from) {
            index = candidate
            break
          }
        }
        if (index < 0) index = matches.length - 1
      } else {
        index = matches.findIndex((range) => range.from >= snapshot.selection.from)
        if (index < 0) index = 0
      }
    } else if (direction) index = (index + Math.sign(direction) + matches.length) % matches.length

    // Set the engine's persistent highlights only when the query changes. Repeated find calls
    // advance selection, so navigation itself selects the engine-provided range directly.
    if (changedQuery || !text) this.editor.find(text, expected)
    this.query = text
    const match = matches[index]
    if (match) this.editor.selectTextRange(match, { reveal: true })
    this.refresh(expected)
    return !!match
  }

  replace(text: string, replacement: string, expected: number, all: boolean): boolean | number {
    const before = this.editor.textSnapshot(expected)
    const previousQuery = this.query
    let result: boolean | number
    try {
      this.find(text, expected)
      result = all
        ? this.editor.replaceAll(text, replacement, expected)
        : this.editor.replace(text, replacement, expected)
    } catch (error) {
      this.query = previousQuery
      this.editor.find(previousQuery, expected)
      this.editor.selectTextRange(before.selection)
      this.refresh(expected)
      throw error
    }
    // A match already equal to the replacement still advances, without adding an undo step.
    if (result || !all) {
      const snapshot = this.editor.textSnapshot(expected)
      const matches = this.matches(text, expected, snapshot.snapshotId)
      const next = matches.find((range) => range.from >= snapshot.selection.to) ?? matches[0]
      if (next) this.editor.selectTextRange(next, { reveal: true })
    }
    this.refresh(expected)
    return result
  }

  private matches(text: string, expected: number, snapshotId: string): readonly TextRange[] {
    if (!text) return []
    if (this.cached?.snapshotId !== snapshotId || this.cached.query !== text)
      this.cached = { snapshotId, query: text, matches: this.editor.searchMatches(text, expected) }
    return this.cached.matches
  }
}

function sameRange(left: TextRange, right: TextRange): boolean {
  return left.snapshotId === right.snapshotId && left.from === right.from && left.to === right.to
}
