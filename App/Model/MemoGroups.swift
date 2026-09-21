import Foundation

/// A section of the side pane.
struct MemoGroup: Identifiable, Equatable {
    let title: String
    var memos: [Memo]

    var id: String { title }
}

extension MemoGroup {
    /// Favorites first, then by when the memo was last edited, in the spans Notes uses: the day, the day
    /// before, the week, the month, then a section per month of this year and one per earlier year.
    /// Memos keep their order within a group.
    static func grouped(_ memos: [Memo], now: Date = .now, calendar: Calendar = .current) -> [MemoGroup] {
        var groups: [MemoGroup] = []
        var index: [String: Int] = [:]
        var newest: [String: Date] = [:]
        for memo in memos {
            let title = memo.favorite ? "Favorites" : span(of: memo.updatedAt, now: now, calendar: calendar)
            if let position = index[title] {
                groups[position].memos.append(memo)
            } else {
                index[title] = groups.count
                groups.append(MemoGroup(title: title, memos: [memo]))
            }
            newest[title] = max(newest[title] ?? .distantPast, memo.favorite ? .distantFuture : memo.updatedAt)
        }
        return groups.sorted { newest[$0.title]! > newest[$1.title]! }
    }

    private static func span(of date: Date, now: Date, calendar: Calendar) -> String {
        let today = calendar.startOfDay(for: now)
        let daysAgo = { (days: Int) in calendar.date(byAdding: .day, value: -days, to: today)! }
        if date >= today { return "Today" }
        if date >= daysAgo(1) { return "Yesterday" }
        if date >= daysAgo(7) { return "Previous 7 Days" }
        if date >= daysAgo(30) { return "Previous 30 Days" }
        let locale = calendar.locale ?? .current
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(Date.FormatStyle(calendar: calendar).month(.wide).locale(locale))
        }
        return date.formatted(Date.FormatStyle(calendar: calendar).year().locale(locale))
    }
}
