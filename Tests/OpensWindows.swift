import Foundation
import Testing

extension Trait where Self == ConditionTrait {
    /// A window a test opens appears on the screen of whoever runs the tests, so a suite that opens one runs only
    /// where the environment asks for it, as CI does.
    static var opensWindows: Self {
        .enabled(
            if: ProcessInfo.processInfo.environment["MEMOS_WINDOW_TESTS"] != nil,
            "set MEMOS_WINDOW_TESTS to run a suite that opens a window"
        )
    }
}
