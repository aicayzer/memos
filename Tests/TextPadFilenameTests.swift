import Foundation
import Testing
@testable import Memos

@Suite struct TextPadFilenameTests {
    @Test func defaultPatternUsesGregorianDateAndPaddedNumber() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-09-25T10:00:00Z"))
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        #expect(try TextPadFilename.name(parts: TextPadFilename.defaultParts, format: .txt,
                                        now: date, number: 1, timeZone: utc) == "2026-09-25-001.txt")
        #expect(try TextPadFilename.name(parts: TextPadFilename.defaultParts, format: .md,
                                        now: date, number: 1204, timeZone: utc) == "2026-09-25-1204.md")
    }

    @Test func customPatternPreservesOrderAndLiteralText() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-01-02T10:00:00Z"))
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        let parts: [TextPadNamePart] = [.literal("Notes "), .token(.number), .literal(" - "), .token(.day), .token(.month)]
        #expect(try TextPadFilename.name(parts: parts, format: .md, now: date,
                                        number: 12, timeZone: utc) == "Notes 012 - 0201.md")
        let encoded = try JSONEncoder().encode(parts)
        #expect(try JSONDecoder().decode([TextPadNamePart].self, from: encoded) == parts)
    }

    @Test func danglingSymlinkCountsAsAnExistingFilename() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "textpad-filenames-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createSymbolicLink(atPath: folder.appending(path: "001.txt").path,
                                                   withDestinationPath: folder.appending(path: "missing.txt").path)
        let available = try TextPadFilename.available(in: folder, parts: [.token(.number)], format: .txt, number: 1)
        #expect(available.url.lastPathComponent == "002.txt")
        #expect(available.number == 2)
    }
}
