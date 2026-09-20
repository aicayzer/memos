import Foundation
import Testing
@testable import Memos

@Suite struct HistoryTests {
    @Test func backAndForwardWalkTheStack() {
        var history = History()
        let a = UUID(), b = UUID(), c = UUID()
        history.push(a); history.push(b); history.push(c)
        #expect(history.back() == b)
        #expect(history.back() == a)
        #expect(history.back() == nil)
        #expect(history.forward() == b)
    }

    @Test func pushingAfterGoingBackDropsTheForwardEntries() {
        var history = History()
        let a = UUID(), b = UUID(), c = UUID()
        history.push(a); history.push(b)
        _ = history.back()
        history.push(c)
        #expect(history.canGoForward == false)
        #expect(history.back() == a)
    }

    @Test func pushingTheCurrentEntryAgainIsIgnored() {
        var history = History()
        let a = UUID()
        history.push(a); history.push(a)
        #expect(history.canGoBack == false)
    }
}
