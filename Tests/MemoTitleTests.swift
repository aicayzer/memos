import Testing
@testable import Memos

@Suite struct MemoTitleTests {
    @Test func firstLineIsTheTitle() {
        #expect(Memo.title(for: "Shopping\n\n- milk\n") == "Shopping")
    }

    @Test func headingMarksAreStripped() {
        #expect(Memo.title(for: "## Plan ##\nbody") == "Plan")
        #expect(Memo.title(for: "#Tight") == "Tight")
    }

    @Test func leadingBlankLinesAreSkipped() {
        #expect(Memo.title(for: "\n  \n\nLater\n") == "Later")
    }

    @Test func emptyMemoIsUntitled() {
        #expect(Memo.title(for: "") == Memo.untitled)
        #expect(Memo.title(for: "\n#\n") == Memo.untitled)
    }
}
