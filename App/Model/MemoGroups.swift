import Foundation

struct MemoGroup: Identifiable {
    let title: String
    var memos: [Memo]

    var id: String { title }
}

extension MemoGroup {
    /// Favorites first, then sections by last edit in the spans the system's own notes app uses. Memos keep
    /// their order within a group.
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
        let style = Date.FormatStyle(
            locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone, capitalizationContext: .standalone
        )
        if calendar.isDate(date, equalTo: now, toGranularity: .year) { return date.formatted(style.month(.wide)) }
        return date.formatted(style.year())
    }
}
