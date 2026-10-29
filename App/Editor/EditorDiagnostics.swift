import CoreFoundation
import Foundation
import Observation

/// Native and JavaScript failures share codes; technical messages never become report data.
struct EditorIncident: Equatable, Sendable {
    static let codes: Set<String> = ["not-ready", "destroyed", "stale-document", "composition", "operation-pending", "read-only", "invalid-argument", "invalid-range", "preservation", "image-unavailable", "diagram-unavailable", "file-unavailable", "clipboard-unavailable", "slash-command-failed", "internal", "script", "navigation", "unavailable", "invalid-response"]
    static let reasons: Set<String> = ["matching-budget", "source-location", "reopen-mismatch", "parse-refusal", "unexpected", "script-error", "unhandled-rejection"]
    let code: String
    let reason: String?
    let generation: Int?
    let revision: Int?

    init(code: String, reason: String? = nil, generation: Int? = nil, revision: Int? = nil) {
        self.code = Self.codes.contains(code) ? code : "unavailable"
        self.reason = reason.flatMap { Self.reasons.contains($0) ? $0 : nil }
        self.generation = generation.flatMap { $0 >= 0 && $0 <= 9_007_199_254_740_991 ? $0 : nil }
        self.revision = revision.flatMap { $0 >= 0 && $0 <= 9_007_199_254_740_991 ? $0 : nil }
    }

    init?(_ body: [String: Any], codeKey: String = "code") {
        guard let code = body[codeKey] as? String else { return nil }
        self.init(code: code, reason: body["reason"] as? String, generation: body["generation"] as? Int, revision: body["revision"] as? Int)
    }

    var fields: [String: Any] {
        var result: [String: Any] = ["code": code]
        if let reason { result["reason"] = reason }
        if let generation { result["generation"] = generation }
        if let revision { result["revision"] = revision }
        return result
    }

    var userMessage: String {
        switch code {
        case "composition": "Finish entering text before trying again."
        case "operation-pending": "An image is still being added. Try again in a moment."
        case "not-ready": "The editor is still loading. Try again in a moment."
        case "stale-document": "Your memo changed. Try again."
        case "preservation": "That edit couldn’t be applied. Your previous text is unchanged."
        default: "The editor couldn’t complete that action. Your text is still open."
        }
    }
}

@MainActor
@Observable
final class EditorDiagnostics {
    static let enabledKey = "recordDiagnosticActivity"
    static let eventLimit = 200
    static let byteLimit = 256 * 1024
    static var defaultIncidentURL: URL {
        URL.applicationSupportDirectory.appending(path: "EditorDiagnostics/incident.json")
    }

    enum Event: String, CaseIterable { case started, loaded, changed, focus, blur, input, command, rejected, snapshot, saved, saveFailed, scriptError, processTerminated, reportRequested, reportUnavailable }
    enum Operation: String, CaseIterable { case load, reload, format, moveBlock, focus, blur, find, replace, replaceAll, setEditingMode, undo, redo, printable, insertPaths, insertImages, pasteAsPlainText, table, pasteNative, imageResponse, clipboardResponse, setAccent, setTextSize, setKeymap, snapshot, rebind, refresh, save, report, navigation }

    private(set) var enabled: Bool
    private(set) var eventCount = 0
    let sessionID = UUID().uuidString
    @ObservationIgnored private var events: [[String: Any]] = []
    @ObservationIgnored private var nativeIncident: [String: Any]?
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var previousIncident: [String: Any]?
    @ObservationIgnored private var engine: [String: Any]?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let incidentURL: URL?
    @ObservationIgnored private let started = ContinuousClock.now
    @ObservationIgnored private var epoch = UUID()
    var recordingEpoch: UUID { epoch }
    var reportAvailable: Bool { enabled && eventCount > 0 }

    init(defaults: UserDefaults, incidentURL: URL? = nil) {
        self.defaults = defaults
        self.incidentURL = incidentURL
        enabled = defaults.bool(forKey: Self.enabledKey)
        if enabled, let incidentURL,
           let size = try? incidentURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= Self.byteLimit,
           let data = try? Data(contentsOf: incidentURL),
           let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            previousIncident = Self.sanitizeReport(raw)
        }
        record(.started)
    }

    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value
        epoch = UUID()
        defaults.set(value, forKey: Self.enabledKey)
        events.removeAll()
        engine = nil
        nativeIncident = nil
        sequence = 0
        previousIncident = nil
        eventCount = 0
        if value { record(.started) }
        else if let incidentURL { try? FileManager.default.removeItem(at: incidentURL) }
    }

    func reset() {
        setEnabled(false)
        defaults.removeObject(forKey: Self.enabledKey)
        if let incidentURL { try? FileManager.default.removeItem(at: incidentURL) }
    }

    func record(_ event: Event, operation: Operation? = nil, generation: Int? = nil, incident: EditorIncident? = nil, composing: Bool? = nil) {
        guard enabled else { return }
        let elapsed = started.duration(to: .now).components
        sequence += 1
        var entry: [String: Any] = ["sequence": sequence, "event": event.rawValue, "elapsedMs": max(0, Int(elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000))]
        if let operation { entry["operation"] = operation.rawValue }
        if let generation, generation >= 0 { entry["generation"] = generation }
        if let incident { entry.merge(incident.fields) { _, new in new } }
        if let composing { entry["composing"] = composing }
        events.append(entry)
        if events.count > Self.eventLimit { events.removeFirst(events.count - Self.eventLimit) }
        eventCount = events.count
        if var captured = nativeIncident {
            var tail = captured["tail"] as? [[String: Any]] ?? []
            if tail.count < 40 { tail.append(entry) }
            captured["tail"] = tail
            nativeIncident = captured
        } else if let incident, !["not-ready", "stale-document", "composition", "operation-pending"].contains(incident.code) {
            nativeIncident = ["triggerSequence": sequence, "events": events, "tail": [[String: Any]]()]
        }
        if incident != nil { persistIncident() }
    }

    func acceptEngineReport(_ report: Any) {
        guard enabled, let raw = report as? [String: Any] else { return }
        engine = Self.sanitizeReport(raw)
    }

    func persistIncident() {
        guard enabled, let incidentURL, let data = encoded(includePrevious: false) else { return }
        do {
            try FileManager.default.createDirectory(at: incidentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: incidentURL, options: [.atomic])
        } catch { /* Diagnostic recording must never interrupt editing or saving. */ }
    }

    func report() -> String? {
        guard enabled, let data = encoded(includePrevious: true) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private var editorVersion: String {
        guard let url = Bundle.main.url(forResource: "editor-version", withExtension: "json", subdirectory: "Editor"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = Self.sanitizeFields(value)["editorVersion"] as? String else { return "unknown" }
        return version
    }

    private func encoded(includePrevious: Bool) -> Data? {
        var result: [String: Any] = ["schemaVersion": 1, "enabled": enabled, "sessionId": sessionID,
            "appVersion": Bundle.main.shortVersion, "appBuild": Bundle.main.buildNumber, "editorVersion": editorVersion, "events": events]
        if let engine { result["engine"] = engine }
        if let nativeIncident { result["nativeIncident"] = nativeIncident }
        if includePrevious, let previousIncident { result["previousIncident"] = previousIncident }
        while let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
            if data.count <= Self.byteLimit { return data }
            result["truncated"] = true
            if result.removeValue(forKey: "previousIncident") != nil { continue }
            if result.removeValue(forKey: "nativeIncident") != nil { continue }
            if var engine = result["engine"] as? [String: Any], engine.removeValue(forKey: "incident") != nil { result["engine"] = engine; continue }
            if result.removeValue(forKey: "engine") != nil { continue }
            return nil
        }
        return nil
    }

    /// The web view is a trust boundary, including fields nominally supplied by the engine.
    static func sanitizeReport(_ raw: [String: Any]) -> [String: Any] {
        var remaining = 2_000
        var report = sanitizeObject(raw, depth: 0, remaining: &remaining)
        if remaining == 0 { report["truncated"] = true }
        return report
    }

    private static func sanitizeObject(_ raw: [String: Any], depth: Int, remaining: inout Int) -> [String: Any] {
        guard depth < 6, remaining > 0 else { return [:] }
        remaining -= 1
        var result = sanitizeFields(raw)
        for key in ["events", "tail"] {
            if let entries = raw[key] as? [[String: Any]] {
                var sanitized: [[String: Any]] = []
                for entry in entries.suffix(key == "tail" ? 40 : 200) {
                    guard remaining > 0 else { break }
                    sanitized.append(sanitizeObject(entry, depth: depth + 1, remaining: &remaining))
                }
                result[key] = sanitized
            }
        }
        for key in ["state", "incident", "nativeIncident", "configuration", "presentation", "caret", "viewport", "scroll", "selection", "engine"] {
            if let value = raw[key] as? [String: Any] { result[key] = sanitizeObject(value, depth: depth + 1, remaining: &remaining) }
        }
        if let marks = raw["marks"] as? [String] {
            result["marks"] = marks.prefix(7).filter { ["strong", "emphasis", "inlineCode", "strike_through", "link", "highlight", "other"].contains($0) }
        }
        return result
    }

    private static func sanitizeFields(_ raw: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        let numeric: Set<String> = ["fontWeight", "headingLevel", "fontSize", "lineHeight", "triggerSequence", "sequence", "elapsedMs", "generation", "revision", "from", "to", "width", "height", "top", "bottom", "left", "right", "schemaVersion"]
        let booleans: Set<String> = ["editable", "pending", "enabled", "composing", "ready", "truncated"]
        let enums: [String: Set<String>] = [
            "code": EditorIncident.codes, "reason": EditorIncident.reasons,
            "kind": ["input", "composition", "focus", "selection", "operation", "preservation", "error", "enabled"],
            "phase": ["before", "after", "start", "end", "in", "out", "begin", "success", "refused"],
            "input": ["text", "composition", "delete", "paste", "drop", "history", "format", "other"],
            "path": ["unchanged", "local", "regions", "whole"],
            "fontStyle": ["normal", "italic", "oblique", "other"],
            "block": ["paragraph", "heading", "code", "other", "literal"],
            "event": Set(Event.allCases.map(\.rawValue)).union(["beforeinput", "input", "compositionstart", "compositionupdate", "compositionend", "selection", "operation", "error", "snapshot", "document", "mode", "focusin", "focusout", "command", "refusal", "transaction"]),
            "type": ["beforeinput", "input", "compositionstart", "compositionend", "focus", "blur", "selection", "operation", "error"],
            "operation": Set(Operation.allCases.map(\.rawValue)).union(["edit", "history", "configuration", "output", "selection", "lifecycle", "other"]), "mode": ["formatted", "source", "txt"], "format": ["md", "txt"],
            "classification": ["script-error", "unhandled-rejection", "unknown"],
        ]
        for (key, value) in raw {
            if numeric.contains(key), let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite, abs(number.doubleValue) <= 9_007_199_254_740_991 { result[key] = number }
            else if booleans.contains(key), let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { result[key] = number }
            else if let allowed = enums[key], let value = value as? String, allowed.contains(value) { result[key] = value }
            else if key == "fontFamily", let value = value as? String { result[key] = sanitizeFontFamily(value) }
            else if key == "caretColor", let value = value as? String, value.count <= 64,
                    value.range(of: "^(#[0-9a-fA-F]{3,8}|rgba?\\([0-9.,% ]+\\))$", options: .regularExpression) != nil { result[key] = value }
            else if ["sessionId"].contains(key), let value = value as? String, let uuid = UUID(uuidString: value) { result[key] = uuid.uuidString }
            else if ["editorVersion", "appVersion", "appBuild"].contains(key), let value = value as? String, value.count <= 32, value.range(of: "^[0-9]+(\\.[0-9]+){0,3}$", options: .regularExpression) != nil { result[key] = value }
        }
        return result
    }
    private static func sanitizeFontFamily(_ value: String) -> String {
        let allowed: Set<String> = ["system-ui", "-apple-system", "BlinkMacSystemFont", "sans-serif", "serif", "monospace", "ui-serif", "ui-sans-serif", "ui-monospace", "ui-rounded", "Arial", "Helvetica", "Helvetica Neue", "SF Pro Text", "SF Pro Display", "SFMono-Regular", "Menlo", "Monaco", "Courier New", "Times New Roman", "Georgia", "Segoe UI"]
        return value.prefix(512).split(separator: ",").prefix(16).map {
            let family = $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return allowed.contains(family) ? family : "other"
        }.joined(separator: ", ")
    }

}

