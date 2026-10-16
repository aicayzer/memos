import Testing
@testable import Memos

struct EditorCommandStateTests {
    @Test func parsesScopedAvailabilityWithoutTreatingNestedMapsAsCommands() throws {
        let message = try #require(EditorMessage(body: [
            "type": "commandState", "documentId": "memo", "generation": 9, "mode": "source",
            "caret": ["marks": ["bold"], "block": ["type": "paragraph"], "quoted": false],
            "commands": ["undo": true, "redo": false, "replace": true, "moveBlockUp": true, "moveBlockDown": false,
                         "format": ["bold": false], "table": ["moveRowUp": false]],
        ]))
        guard case .commandState(let state, let id, let generation) = message else {
            Issue.record("Expected scoped command state"); return
        }
        #expect(id == "memo")
        #expect(generation == 9)
        #expect(state.sourceMode)
        #expect(state.commands["undo"] == true)
        #expect(state.commands["moveBlockUp"] == true)
        #expect(state.commands["moveBlockDown"] == false)
        #expect(state.commands["format"] == nil)
        #expect(state.formats["bold"] == false)
        #expect(state.tables["moveRowUp"] == false)
    }

    @Test func readsEachHeadingLevelAsItsOwnFormat() throws {
        let message = try #require(EditorMessage(body: [
            "type": "commandState", "documentId": "memo", "generation": 1, "mode": "formatted",
            "caret": ["marks": [], "block": ["type": "heading", "level": 2], "quoted": false],
            "commands": ["format": ["heading1": true, "heading2": false, "heading3": true, "bold": true]],
        ]))
        guard case .commandState(let state, _, _) = message else {
            Issue.record("Expected scoped command state"); return
        }
        #expect(state.block == .heading(2))
        #expect(state.formats["heading1"] == true)
        #expect(state.formats["heading2"] == false)
        #expect(state.formats["heading"] == nil)
    }

    @Test func unscopedCommandStateIsRejected() {
        #expect(EditorMessage(body: ["type": "commandState", "generation": 1]) == nil)
    }
}
