import Testing
@testable import Memos

@Suite struct MemoTitleTests {
    @Test func firstLineIsTheTitle() {
        #expect(Memo.title(for: "Shopping\n\n- milk\n") == "Shopping")
    }

    @Test func headingMarksAreStripped() {
        #expect(Memo.title(for: "## Plan ##\nbody") == "Plan")
        #expect(Memo.title(for: "#Tight") == "Tight")
        #expect(Memo.title(for: "# C#") == "C#")
    }

    @Test func blockMarkersAreStripped() {
        #expect(Memo.title(for: "> Markdown Reference\n") == "Markdown Reference")
        #expect(Memo.title(for: "> > Nested\n") == "Nested")
        #expect(Memo.title(for: "- milk\n- eggs\n") == "milk")
        #expect(Memo.title(for: "* milk\n") == "milk")
        #expect(Memo.title(for: "1. First step\n") == "First step")
        #expect(Memo.title(for: "12) Twelfth\n") == "Twelfth")
        #expect(Memo.title(for: "- [ ] Call the bank\n") == "Call the bank")
        #expect(Memo.title(for: "- [x] Done\n") == "Done")
        #expect(Memo.title(for: "> - [ ] **Call**\n") == "Call")
    }

    @Test func inlineMarksAreStripped() {
        #expect(Memo.title(for: "**Bold** and *italic* and ~~gone~~ and `code`") == "Bold and italic and gone and code")
        #expect(Memo.title(for: "***Both***") == "Both")
        #expect(Memo.title(for: "[Site](https://example.com) and <https://example.com/page>") == "Site and https://example.com/page")
        #expect(Memo.title(for: "_Quiet_ start") == "Quiet start")
    }

    @Test func wordsAreLeftAlone() {
        #expect(Memo.title(for: "snake_case_name") == "snake_case_name")
        #expect(Memo.title(for: "2 * 3 = 6") == "2 * 3 = 6")
        #expect(Memo.title(for: "-not a list") == "-not a list")
        #expect(Memo.title(for: "2024 in review") == "2024 in review")
    }

    @Test func fencesAndRulesAreSkipped() {
        #expect(Memo.title(for: "```swift\nlet x = 1\n```\n") == "let x = 1")
        #expect(Memo.title(for: "---\nAfter the rule\n") == "After the rule")
        #expect(Memo.title(for: "-\n- \nItem\n") == "Item")
    }

    @Test func windowsLineEndingsSplitLines() {
        #expect(Memo.title(for: "First\r\nSecond\r\n") == "First")
    }

    @Test func leadingBlankLinesAreSkipped() {
        #expect(Memo.title(for: "\n  \n\nLater\n") == "Later")
    }

    @Test func emptyMemoIsUntitled() {
        #expect(Memo.title(for: "") == Memo.untitled)
        #expect(Memo.title(for: "\n#\n") == Memo.untitled)
        #expect(Memo.title(for: "> \n") == Memo.untitled)
    }
}
