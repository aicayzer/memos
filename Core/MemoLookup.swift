import Foundation

/// How the command line names a memo: an id, the start of one, a title, or the start of one.
enum MemoLookup {
    enum Failure: Error, Equatable {
        case none(String)
        case several(String, [Memo])
    }

    static func find(_ reference: String, in memos: [Memo]) throws -> Memo {
        let needle = reference.trimmingCharacters(in: .whitespaces)
        if let id = UUID(uuidString: needle), let memo = memos.first(where: { $0.id == id }) { return memo }
        let candidates = [
            memos.filter { $0.id.uuidString.lowercased().hasPrefix(needle.lowercased()) && needle.count >= 4 },
            memos.filter { $0.title.caseInsensitiveCompare(needle) == .orderedSame },
            memos.filter { $0.title.lowercased().hasPrefix(needle.lowercased()) },
        ]
        for matches in candidates {
            if matches.count == 1 { return matches[0] }
            if matches.count > 1 { throw Failure.several(needle, matches) }
        }
        throw Failure.none(needle)
    }
}
