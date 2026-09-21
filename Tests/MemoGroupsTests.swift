import Foundation
import Testing
@testable import Memos

@Suite struct MemoGroupsTests {
    private static func calendar(_ zone: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private let calendar = Self.calendar()

    // Wednesday 20 May 2026, 16:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_779_292_800)

    private func memo(_ title: String, at date: Date, favorite: Bool = false) -> Memo {
        Memo(id: UUID(), markdown: title, favorite: favorite, createdAt: date, updatedAt: date)
    }

    private func memo(_ title: String, daysAgo: Double, favorite: Bool = false) -> Memo {
        memo(title, at: now.addingTimeInterval(-daysAgo * 86_400), favorite: favorite)
    }

    private func titles(_ memos: [Memo], now: Date? = nil, calendar: Calendar? = nil) -> [String] {
        MemoGroup.grouped(memos, now: now ?? self.now, calendar: calendar ?? self.calendar).map(\.title)
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

    @Test func spansTurnAtMidnight() {
        let today = calendar.startOfDay(for: now)
        let day = { (days: Int) in calendar.date(byAdding: .day, value: -days, to: today)! }
        #expect(titles([memo("first second", at: today)]) == ["Today"])
        #expect(titles([memo("last second", at: today - 1)]) == ["Yesterday"])
        #expect(titles([memo("first second", at: day(1))]) == ["Yesterday"])
        #expect(titles([memo("last second", at: day(1) - 1)]) == ["Previous 7 Days"])
        #expect(titles([memo("first second", at: day(7))]) == ["Previous 7 Days"])
        #expect(titles([memo("last second", at: day(7) - 1)]) == ["Previous 30 Days"])
        #expect(titles([memo("first second", at: day(30))]) == ["Previous 30 Days"])
        #expect(titles([memo("last second", at: day(30) - 1)]) == ["April"])
    }

    @Test func lastYearIsAYearOnceOutOfTheMonth() {
        // Saturday 10 January 2026, noon UTC.
        let january = Date(timeIntervalSince1970: 1_768_046_400)
        let december = calendar.date(byAdding: .day, value: -21, to: january)!
        let november = calendar.date(byAdding: .day, value: -50, to: january)!
        #expect(titles([memo("recent", at: december), memo("older", at: november)], now: january) == ["Previous 30 Days", "2025"])
    }

    @Test func monthsThenYearsDescend() {
        let april = calendar.date(byAdding: .day, value: -45, to: now)!
        let march = calendar.date(byAdding: .day, value: -70, to: now)!
        let lastYear = calendar.date(byAdding: .year, value: -1, to: now)!
        let earlier = calendar.date(byAdding: .year, value: -2, to: now)!
        let memos = [memo("earlier", at: earlier), memo("march", at: march), memo("april", at: april), memo("last year", at: lastYear)]
        #expect(titles(memos) == ["April", "March", "2025", "2024"])
    }

    @Test func clockChangeKeepsTheDay() {
        // The day after the clocks went forward in London, at noon.
        let london = Self.calendar("Europe/London")
        let dayAfter = london.date(from: DateComponents(year: 2026, month: 3, day: 30, hour: 12))!
        let earlyThatMorning = london.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 0, minute: 30))!
        let nightBefore = london.date(from: DateComponents(year: 2026, month: 3, day: 28, hour: 23, minute: 30))!
        #expect(titles([memo("after", at: earlyThatMorning)], now: dayAfter, calendar: london) == ["Yesterday"])
        #expect(titles([memo("before", at: nightBefore)], now: dayAfter, calendar: london) == ["Previous 7 Days"])
    }

    @Test func favoritesComeFirstWhateverTheirDate() {
        let memos = [memo("today", daysAgo: 0), memo("starred", daysAgo: 400, favorite: true)]
        #expect(titles(memos) == ["Favorites", "Today"])
    }

    @Test func groupsAreNewestFirstWhateverTheListOrder() {
        let memos = [memo("old", daysAgo: 20), memo("new", daysAgo: 0), memo("older", daysAgo: 3)]
        #expect(titles(memos) == ["Today", "Previous 7 Days", "Previous 30 Days"])
    }

    @Test func aFutureDateCountsAsToday() {
        #expect(titles([memo("ahead", daysAgo: -2)]) == ["Today"])
    }

    @Test func emptyListHasNoGroups() {
        #expect(MemoGroup.grouped([], now: now, calendar: calendar).isEmpty)
    }
}
