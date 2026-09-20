import Foundation
import Testing
@testable import Memos

@Test func bundleHasADisplayName() {
    #expect(!Bundle.main.displayName.isEmpty)
}
