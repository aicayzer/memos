import AppKit
import Testing
@testable import Memos

@MainActor
@Suite struct LoginLaunchTests {
    @Test func ordinaryLaunchShowsTheWindow() {
        #expect(!LoginItemSettings.isLoginLaunch(nil))
        let event = NSAppleEventDescriptor(eventClass: kCoreEventClass, eventID: kAEOpenApplication,
                                          targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        #expect(!LoginItemSettings.isLoginLaunch(event))
    }

    @Test(arguments: [keyAELaunchedAsLogInItem, keyAELaunchedAsServiceItem])
    func loginAndServiceLaunchesStartInBackground(_ kind: AEKeyword) {
        let event = NSAppleEventDescriptor(eventClass: kCoreEventClass, eventID: kAEOpenApplication,
                                          targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(enumCode: kind), forKeyword: keyAEPropData)
        #expect(LoginItemSettings.isLoginLaunch(event))
    }
}
