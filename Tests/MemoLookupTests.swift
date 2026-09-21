import Foundation
import Testing
@testable import Memos

@Suite struct MemoLookupTests {
    private let memos = [
        Memo(id: UUID(uuidString: "6A3F2C8E-0000-4000-8000-000000000001")!, markdown: "# Shopping\n", favorite: false, createdAt: .now, updatedAt: .now),
        Memo(id: UUID(uuidString: "6A3F2C8E-0000-4000-8000-000000000002")!, markdown: "Shop floor notes\n", favorite: false, createdAt: .now, updatedAt: .now),
        Memo(id: UUID(uuidString: "B1000000-0000-4000-8000-000000000003")!, markdown: "Plan\n", favorite: false, createdAt: .now, updatedAt: .now),
    ]

    @Test func byIdThenPrefixThenTitle() throws {
        #expect(try MemoLookup.find("b1000000-0000-4000-8000-000000000003", in: memos).title == "Plan")
        #expect(try MemoLookup.find("b100", in: memos).title == "Plan")
        #expect(try MemoLookup.find("shopping", in: memos).title == "Shopping")
        #expect(try MemoLookup.find("pl", in: memos).title == "Plan")
    }

    @Test func ambiguityAndAbsenceAreNamed() {
        #expect(throws: MemoLookup.Failure.several("6a3f", [memos[0], memos[1]])) { try MemoLookup.find("6a3f", in: memos) }
        #expect(throws: MemoLookup.Failure.several("shop", [memos[0], memos[1]])) { try MemoLookup.find("shop", in: memos) }
        #expect(throws: MemoLookup.Failure.none("zzz")) { try MemoLookup.find("zzz", in: memos) }
        // Too short a prefix could match anything, so it is a title.
        #expect(throws: MemoLookup.Failure.none("6a3")) { try MemoLookup.find("6a3", in: memos) }
    }
}
