import Foundation
import Darwin

enum TextPadNameToken: String, Codable, CaseIterable, Identifiable {
    case year, month, day, number

    var id: String { rawValue }
    var title: String {
        switch self {
        case .year: "Year"
        case .month: "Month"
        case .day: "Day"
        case .number: "Number"
        }
    }
}

enum TextPadNamePart: Codable, Equatable {
    case literal(String)
    case token(TextPadNameToken)
}

enum TextPadFilename {
    static let defaultParts: [TextPadNamePart] = [
        .token(.year), .literal("-"), .token(.month), .literal("-"), .token(.day), .literal("-"), .token(.number)
    ]

    static func name(parts: [TextPadNamePart], format: TextPadFormat, now: Date = .now,
                     number: Int, timeZone: TimeZone = .current) throws -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        let stem = parts.map { part in
            switch part {
            case let .literal(value): value
            case .token(.year): String(format: "%04d", components.year ?? 0)
            case .token(.month): String(format: "%02d", components.month ?? 0)
            case .token(.day): String(format: "%02d", components.day ?? 0)
            case .token(.number): String(format: "%03lld", Int64(number))
            }
        }.joined()
        return try filename(stem: stem, extension: format.rawValue)
    }

    static func filename(stem: String, extension fileExtension: String) throws -> String {
        let stem = try validatedStem(stem)
        let filename = "\(stem).\(fileExtension)"
        guard filename.utf8.count <= 255 else { throw TextPadError.invalidName }
        return filename
    }

    static func validatedStem(_ input: String) throws -> String {
        let stem = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.rangeOfCharacter(from: .controlCharacters) == nil,
              !stem.isEmpty, stem != ".", stem != "..",
              !stem.contains("/"), !stem.contains("\\"), !stem.contains(":"),
              stem.utf8.count <= 255 else {
            throw TextPadError.invalidName
        }
        return stem
    }

    static func available(in folder: URL, parts: [TextPadNamePart], format: TextPadFormat,
                          now: Date = .now, number: Int) throws -> (url: URL, number: Int) {
        let hasNumber = parts.contains(.token(.number))
        var candidateNumber = number
        var suffix = 1
        while true {
            let name = try name(parts: parts, format: format, now: now, number: candidateNumber)
            let candidate: URL
            if hasNumber || suffix == 1 {
                candidate = folder.appending(path: name)
            } else {
                let stem = String(name.dropLast(format.rawValue.count + 1))
                candidate = folder.appending(path: try filename(stem: "\(stem)-\(suffix)", extension: format.rawValue))
            }
            var attributes = stat()
            let exists = candidate.withUnsafeFileSystemRepresentation { lstat($0!, &attributes) == 0 }
            guard exists else { return (candidate, candidateNumber) }
            if hasNumber {
                guard candidateNumber < Int.max - 1 else { throw TextPadError.invalidName }
                candidateNumber += 1
            } else {
                suffix += 1
            }
        }
    }
}
