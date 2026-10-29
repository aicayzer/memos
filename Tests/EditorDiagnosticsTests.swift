import AppKit
import Foundation
import Testing
@testable import Memos

@MainActor
@Suite struct EditorDiagnosticsTests {
    private func fixture() throws -> (EditorDiagnostics, UserDefaults, URL, String) {
        let name = "diagnostics-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let folder = try temporaryFolder()
        return (EditorDiagnostics(defaults: defaults, incidentURL: folder.appending(path: "incident.json")), defaults, folder, name)
    }

    @Test func persistedOptInIsAttachedBeforeTheFirstDocumentLoad() throws {
        let (recorder, defaults, folder, name) = try fixture()
        defer { discard(folder); defaults.removePersistentDomain(forName: name) }
        recorder.setEnabled(true)
        let relaunched = EditorDiagnostics(defaults: defaults, incidentURL: folder.appending(path: "incident.json"))
        let editor = FakeEditor()
        let model = AppModel(store: ChangeableStore([]), images: FakeImageStore(), defaults: defaults, editor: editor, diagnostics: relaunched)
        #expect(model.diagnostics.enabled)
        #expect(editor.diagnostics === relaunched)
        #expect(editor.diagnostics?.enabled == true)
    }

    @Test func recordingStartsOffAndDoesNotWriteFiles() throws {
        let (recorder, defaults, folder, name) = try fixture()
        defer { discard(folder); defaults.removePersistentDomain(forName: name) }
        recorder.record(.rejected, incident: EditorIncident(code: "preservation"))
        recorder.acceptEngineReport(["events": [["kind": "input"]]])
        recorder.persistIncident()
        #expect(!recorder.enabled)
        #expect(!recorder.reportAvailable)
        #expect(recorder.eventCount == 0)
        #expect(recorder.report() == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        #expect(defaults.object(forKey: EditorDiagnostics.enabledKey) == nil)
    }

    @Test func enablingPersistsAndDisablingClearsCurrentAndPreviousActivity() throws {
        let (recorder, defaults, folder, name) = try fixture()
        defer { discard(folder); defaults.removePersistentDomain(forName: name) }
        let file = folder.appending(path: "incident.json")
        recorder.setEnabled(true)
        recorder.record(.rejected, incident: EditorIncident(code: "preservation", reason: "reopen-mismatch", generation: 4, revision: 9))
        #expect(FileManager.default.fileExists(atPath: file.path))
        let relaunched = EditorDiagnostics(defaults: defaults, incidentURL: file)
        #expect(relaunched.enabled)
        #expect(relaunched.report()?.contains("previousIncident") == true)
        #expect(relaunched.sessionID != recorder.sessionID)
        relaunched.setEnabled(false)
        #expect(!defaults.bool(forKey: EditorDiagnostics.enabledKey))
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(relaunched.report() == nil)
        relaunched.setEnabled(true)
        #expect(relaunched.report()?.contains("previousIncident") == false)
        relaunched.reset()
        #expect(defaults.object(forKey: EditorDiagnostics.enabledKey) == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func historyAndIncidentAreBoundedAndUntrustedFieldsNeverSurvive() throws {
        let (recorder, defaults, folder, name) = try fixture()
        defer { discard(folder); defaults.removePersistentDomain(forName: name) }
        recorder.setEnabled(true)
        for _ in 0..<1000 { recorder.record(.input, generation: 1) }
        let canary = "PRIVATE memo title text filename /private/file https://secret.test"
        let event: [String: Any] = ["kind": "preservation", "phase": "refused", "code": "preservation", "reason": "reopen-mismatch", "message": canary, "data": canary, "inputType": canary, "documentId": canary, "operation": canary, "state": ["generation": 1, "revision": 5, "text": canary]]
        recorder.acceptEngineReport(["enabled": true, "sessionId": UUID().uuidString, "editorVersion": "0.5.0", "events": Array(repeating: event, count: 900), "incident": ["triggerSequence": 12, "events": Array(repeating: event, count: 900), "tail": Array(repeating: event, count: 90)], "presentation": ["fontSize": 15, "fontFamily": canary, "caretColor": canary, "viewport": ["width": 400, "height": 600, "html": canary]], "message": canary])
        recorder.record(.rejected, incident: EditorIncident(code: "preservation", reason: canary, generation: 1, revision: 5))
        let report = try #require(recorder.report())
        #expect(recorder.eventCount == EditorDiagnostics.eventLimit)
        #expect(report.utf8.count <= EditorDiagnostics.byteLimit)
        #expect(!report.contains(canary))
        #expect(!report.contains("documentId"))
        #expect(!report.contains("message"))
        #expect(report.contains("reopen-mismatch"))
        let parsed = try #require(JSONSerialization.jsonObject(with: Data(report.utf8)) as? [String: Any])
        let engine = try #require(parsed["engine"] as? [String: Any])
        #expect((engine["events"] as? [Any])?.count == 200)
        let incident = try #require(engine["incident"] as? [String: Any])
        #expect((incident["events"] as? [Any])?.count == 200)
        #expect((incident["tail"] as? [Any])?.count == 40)
        let persisted = try Data(contentsOf: folder.appending(path: "incident.json"))
        #expect(persisted.count <= EditorDiagnostics.byteLimit)
        #expect(!String(decoding: persisted, as: UTF8.self).contains(canary))
    }

    @Test func copyingWorksWithoutSnapshotAndOptOutDuringCollectionKeepsClipboard() async throws {
        let (recorder, defaults, folder, name) = try fixture()
        defer { discard(folder); defaults.removePersistentDomain(forName: name) }
        let editor = FakeEditor()
        editor.snapshotError = MemoEditorError.snapshotRejected(code: "composition", message: "PRIVATE writing")
        editor.diagnosticData = Data("{\"enabled\":true,\"events\":[{\"kind\":\"composition\",\"phase\":\"start\"}]}".utf8)
        let model = AppModel(store: ChangeableStore([]), images: FakeImageStore(), defaults: defaults, editor: editor, diagnostics: recorder, presentError: { _ in })
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Untouched clipboard", forType: .string)
        await model.copyDiagnosticReport(to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "Untouched clipboard")
        model.setDiagnosticsEnabled(true)
        await model.copyDiagnosticReport(to: pasteboard)
        #expect(pasteboard.string(forType: .string)?.contains("composition") == true)
        #expect(pasteboard.string(forType: .string)?.contains("PRIVATE") == false)
        pasteboard.clearContents()
        pasteboard.setString("Keep clipboard", forType: .string)
        editor.duringDiagnosticReport = { model.setDiagnosticsEnabled(false) }
        await model.copyDiagnosticReport(to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "Keep clipboard")
        #expect(!recorder.enabled)
    }

    @Test func hostileNestedReportsStayBoundedAndLeaveNativeHistoryAvailable() throws {
        let (recorder, defaults, folder, name) = try fixture()
        defer { discard(folder); defaults.removePersistentDomain(forName: name) }
        recorder.setEnabled(true)
        var nested: [String: Any] = ["kind": "input", "sequence": 1]
        for _ in 0..<4 { nested = ["events": Array(repeating: nested, count: 200)] }
        recorder.acceptEngineReport(nested)
        let report = try #require(recorder.report())
        #expect(report.utf8.count <= EditorDiagnostics.byteLimit)
        #expect(report.contains("started"))
        #expect(report.contains("truncated"))
    }

    @Test func firstNativeIncidentKeepsTwoHundredEventsAndFortyFollowups() throws {
        let (recorder, defaults, folder, name) = try fixture()
        defer { discard(folder); defaults.removePersistentDomain(forName: name) }
        recorder.setEnabled(true)
        for _ in 0..<240 { recorder.record(.input, generation: 1) }
        recorder.record(.rejected, generation: 1, incident: EditorIncident(code: "preservation"))
        for _ in 0..<60 { recorder.record(.input, generation: 1) }
        recorder.record(.rejected, generation: 1, incident: EditorIncident(code: "internal"))
        let report = try #require(recorder.report())
        let parsed = try #require(JSONSerialization.jsonObject(with: Data(report.utf8)) as? [String: Any])
        let incident = try #require(parsed["nativeIncident"] as? [String: Any])
        #expect(incident["triggerSequence"] as? Int == 242)
        let events = try #require(incident["events"] as? [[String: Any]])
        #expect(events.count == 200)
        #expect(events.last?["code"] as? String == "preservation")
        let tail = try #require(incident["tail"] as? [[String: Any]])
        #expect(tail.count == 40)
        #expect(tail.last?["sequence"] as? Int == 282)
    }

    @Test func unavailableEditorReportCopiesTheCachedNativeIncident() async throws {
        let (recorder, defaults, folder, name) = try fixture()
        defer { discard(folder); defaults.removePersistentDomain(forName: name) }
        let editor = FakeEditor()
        editor.diagnosticError = MemoEditorError.unavailable
        let model = AppModel(store: ChangeableStore([]), images: FakeImageStore(), defaults: defaults, editor: editor, diagnostics: recorder, presentError: { _ in })
        model.setDiagnosticsEnabled(true)
        recorder.record(.rejected, incident: EditorIncident(code: "preservation", reason: "reopen-mismatch"))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        await model.copyDiagnosticReport(to: pasteboard)
        let report = try #require(pasteboard.string(forType: .string))
        #expect(report.contains("nativeIncident"))
        #expect(report.contains("preservation"))
        #expect(report.contains("reportUnavailable"))
    }

    @Test func nativeErrorsKeepOnlyKnownCodesAndDiscardTheirMessages() throws {
        let canary = "PRIVATE exception containing memo contents"
        let incident = EditorIncident(error: MemoEditorError.snapshotRejected(code: "preservation", message: canary))
        #expect(incident.code == "preservation")
        let unknown = EditorIncident(error: MemoEditorError.snapshotRejected(code: canary, message: canary))
        #expect(unknown.code == "unavailable")
        let encoded = try JSONSerialization.data(withJSONObject: ["known": incident.fields, "unknown": unknown.fields])
        #expect(!String(decoding: encoded, as: UTF8.self).contains(canary))
        #expect(EditorIncident(error: MemoEditorError.documentChanged).code == "stale-document")
    }

    @Test func fontStacksKeepOnlyKnownFamilies() throws {
        let report = EditorDiagnostics.sanitizeReport(["presentation": ["fontFamily": "-apple-system, BlinkMacSystemFont, system-ui, sans-serif, \"Times New Roman\", Georgia, ui-rounded, PRIVATE-memo-title", "fontWeight": 600, "fontStyle": "italic", "headingLevel": 2]])
        let presentation = try #require(report["presentation"] as? [String: Any])
        #expect(presentation["fontFamily"] as? String == "-apple-system, BlinkMacSystemFont, system-ui, sans-serif, Times New Roman, Georgia, ui-rounded, other")
        #expect(presentation["fontWeight"] as? Int == 600)
        #expect(presentation["headingLevel"] as? Int == 2)
    }

    @Test func bridgeWarningsKeepOnlyStructuredDetailsAndFixedUserCopy() throws {
        let canary = "PRIVATE exception containing memo contents"
        let parsed = try #require(EditorMessage(body: ["type": "editorWarning", "code": "preservation", "reason": "reopen-mismatch", "generation": 2, "revision": 7, "message": canary]))
        guard case .incident(let incident) = parsed else { Issue.record("Expected structured incident"); return }
        #expect(incident.code == "preservation")
        #expect(incident.generation == 2)
        #expect(incident.revision == 7)
        #expect(incident.reason == "reopen-mismatch")
        #expect(!incident.userMessage.contains(canary))
        #expect(incident.userMessage == "That edit couldn’t be applied. Your previous text is unchanged.")
    }
}
