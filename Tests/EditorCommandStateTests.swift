import Testing
@testable import Memos

struct EditorCommandStateTests {
    @Test func parsesScopedAvailabilityWithoutTreatingNestedMapsAsCommands() throws {
        let message = try #require(EditorMessage(body: [
            "type": "commandState", "documentId": "memo", "generation": 9, "mode": "source",
            "caret": ["marks": ["bold"], "block": ["type": "paragraph"], "quoted": false],
            "commands": ["undo": true, "redo": false, "replace": true,
                         "format": ["bold": false], "table": ["moveRowUp": false]],
        ]))
        guard case .commandState(let state, let id, let generation) = message else {
            Issue.record("Expected scoped command state"); return
        }
        #expect(id == "memo")
        #expect(generation == 9)
        #expect(state.sourceMode)
        #expect(state.commands["undo"] == true)
        #expect(state.commands["format"] == nil)
        #expect(state.formats["bold"] == false)
        #expect(state.tables["moveRowUp"] == false)
    }

    @Test func unscopedCommandStateIsRejected() {
        #expect(EditorMessage(body: ["type": "commandState", "generation": 1]) == nil)
    }
}
