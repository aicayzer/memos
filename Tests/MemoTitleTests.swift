import Testing
@testable import Memos

@Suite struct MemoTitleTests {
    @Test func theTitleBarCutsLongTitlesAtAWord() {
        #expect(Memo.abbreviated("Shortcuts aren't right") == "Shortcuts aren't…")
        #expect(Memo.abbreviated("Twenty characters!!!") == "Twenty characters!!!")
        #expect(Memo.abbreviated("Twenty characters!!! and more") == "Twenty characters!!!…")
        // A long word keeps the full cut rather than falling back to a stub.
        #expect(Memo.abbreviated("A supercalifragilisticexpialidocious word") == "A supercalifragilist…")
        #expect(Memo.abbreviated("https://example.com/a/long/path") == "https://example.com/…")
        #expect(Memo.abbreviated("Short", to: 3) == "Sho…")
    }

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
        #expect(Memo.title(for: "![Photo](photo.png) of the day") == "Photo of the day")
        #expect(Memo.title(for: "_Quiet_ start") == "Quiet start")
    }

    @Test func headingTextIsPlain() {
        #expect(Memo.title(for: "# 1. Introduction") == "1. Introduction")
        #expect(Memo.title(for: "# - dash") == "- dash")
        #expect(Memo.title(for: "> # Quoted heading") == "Quoted heading")
    }

    // The store holds remark's output, which escapes punctuation that could read as markdown.
    @Test func escapesAndCodeAreLiteral() {
        #expect(Memo.title(for: "2 \\* 3 = 6") == "2 * 3 = 6")
        #expect(Memo.title(for: "a \\*\\* b \\*\\* c") == "a ** b ** c")
        #expect(Memo.title(for: "\\#hashtag") == "#hashtag")
        #expect(Memo.title(for: "`a*b*c` and *x*") == "a*b*c and x")
        #expect(Memo.title(for: "\\[not a link](x)") == "[not a link](x)")
    }

    @Test func characterReferencesAreDecoded() {
        #expect(Memo.title(for: "Memos&#x20;") == "Memos")
        #expect(Memo.title(for: "&#x20; Indented") == "Indented")
        #expect(Memo.title(for: "Tab&#9;stop") == "Tab\tstop")
        #expect(Memo.title(for: "Star &#x2A;not italic&#x2A;") == "Star *not italic*")
        // A letter next to an emphasis whose text starts with a space is encoded; the marks must go first.
        #expect(Memo.title(for: "fo&#x6F;*&#x20;bar*") == "foo bar")
        #expect(Memo.title(for: "**&#x20;both&#x20;**&#x78;") == "both x")
        #expect(Memo.title(for: "&#x20;\n\nSecond line") == "Second line")
        #expect(Memo.title(for: "`&#x20;`") == "&#x20;")
        #expect(Memo.title(for: "\\&#x20;") == "&#x20;")
        #expect(Memo.title(for: "&#x110000; stays") == "&#x110000; stays")
    }

    @Test func hardBreakIsNotPartOfTheTitle() {
        #expect(Memo.title(for: "Memos\\\nReference") == "Memos")
        #expect(Memo.title(for: "Memos&#x20;\\\nReference") == "Memos")
        #expect(Memo.title(for: "Ends in \\\\") == "Ends in \\")
    }

    @Test func wordsAreLeftAlone() {
        #expect(Memo.title(for: "snake_case_name") == "snake_case_name")
        #expect(Memo.title(for: "2 * 3 = 6") == "2 * 3 = 6")
        #expect(Memo.title(for: "-not a list") == "-not a list")
        #expect(Memo.title(for: "2024 in review") == "2024 in review")
        #expect(Memo.title(for: "١. Arabic digits are words") == "١. Arabic digits are words")
    }

    @Test func longLinesAreBounded() {
        let brackets = String(repeating: "[", count: 20_000)
        #expect(Memo.title(for: brackets).count == 300)
        let links = String(repeating: "<https://", count: 2_000)
        #expect(Memo.title(for: links).count == 300)
    }

    @Test func fencesAndRulesAreSkipped() {
        #expect(Memo.title(for: "```swift\nlet x = 1\n```\n") == "let x = 1")
        #expect(Memo.title(for: "> ```\n> quoted code\n> ```\n") == "quoted code")
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

@Suite struct MemoFileNameTests {
    @Test func titleBecomesMarkdownFileName() {
        #expect(Memo.fileName(for: "Weekly plan") == "Weekly plan.md")
    }

    @Test func separatorsBecomeDashes() {
        #expect(Memo.fileName(for: "Q3: costs / income") == "Q3- costs - income.md")
    }

    @Test func emptyAndDotLeadingTitlesFallBack() {
        #expect(Memo.fileName(for: "") == "Untitled.md")
        #expect(Memo.fileName(for: ".hidden") == "Untitled.md")
    }

    @Test func longTitlesAreCut() {
        let name = Memo.fileName(for: String(repeating: "a", count: 200))
        #expect(name == String(repeating: "a", count: 80) + ".md")
        let cutAtSpace = Memo.fileName(for: String(repeating: "a", count: 79) + " b c")
        #expect(cutAtSpace == String(repeating: "a", count: 79) + ".md")
        let emoji = Memo.fileName(for: String(repeating: "🏳️‍🌈", count: 80))
        #expect(emoji.utf8.count <= 203)
    }

    @Test func outerWhitespaceIsTrimmed() {
        #expect(Memo.fileName(for: "  Plan  ") == "Plan.md")
    }
}

@Suite struct MemoAppendingTests {
    @Test func textJoinsAsAParagraph() {
        #expect(Memo.appending("- milk", to: "# Shopping\n") == "# Shopping\n\n- milk\n")
        #expect(Memo.appending("- milk", to: "# Shopping") == "# Shopping\n\n- milk\n")
        #expect(Memo.appending("- milk\n", to: "# Shopping\n\n\n") == "# Shopping\n\n- milk\n")
        #expect(Memo.appending("First", to: "") == "First\n")
    }
}
