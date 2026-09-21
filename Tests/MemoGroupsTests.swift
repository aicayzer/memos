import Foundation
import Testing
@testable import Memos

@Suite struct MemoGroupsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    // Wednesday 20 May 2026, mid-afternoon.
    private let now = Date(timeIntervalSince1970: 1_779_292_800)

    private func memo(_ title: String, daysAgo: Double, favorite: Bool = false) -> Memo {
        let date = now.addingTimeInterval(-daysAgo * 86_400)
        return Memo(id: UUID(), markdown: title, favorite: favorite, createdAt: date, updatedAt: date)
    }

    @Test func spansFollowTheDay() {
        let memos = [
            memo("now", daysAgo: 0), memo("this morning", daysAgo: 0.5), memo("yesterday", daysAgo: 1),
            memo("three days", daysAgo: 3), memo("a week", daysAgo: 7), memo("two weeks", daysAgo: 14),
            memo("a month", daysAgo: 30), memo("six weeks", daysAgo: 45), memo("last year", daysAgo: 300),
        ]
        let groups = MemoGroup.grouped(memos, now: now, calendar: calendar)
        #expect(groups.map(\.title) == ["Today", "Yesterday", "Previous 7 Days", "Previous 30 Days", "April", "2025"])
        #expect(groups.map { $0.memos.map(\.title) } == [
            ["now", "this morning"], ["yesterday"], ["three days", "a week"], ["two weeks", "a month"], ["six weeks"], ["last year"],
        ])
    }

    @Test func favoritesComeFirstWhateverTheirDate() {
        let memos = [memo("today", daysAgo: 0), memo("starred", daysAgo: 400, favorite: true)]
        let groups = MemoGroup.grouped(memos, now: now, calendar: calendar)
        #expect(groups.map(\.title) == ["Favorites", "Today"])
    }

    @Test func groupsAreNewestFirstWhateverTheListOrder() {
        let memos = [memo("old", daysAgo: 20), memo("new", daysAgo: 0), memo("older", daysAgo: 3)]
        let groups = MemoGroup.grouped(memos, now: now, calendar: calendar)
        #expect(groups.map(\.title) == ["Today", "Previous 7 Days", "Previous 30 Days"])
    }

    @Test func aFutureDateCountsAsToday() {
        let groups = MemoGroup.grouped([memo("ahead", daysAgo: -2)], now: now, calendar: calendar)
        #expect(groups.map(\.title) == ["Today"])
    }

    @Test func emptyListHasNoGroups() {
        #expect(MemoGroup.grouped([], now: now, calendar: calendar).isEmpty)
    }
}
