import XCTest
@testable import TennisClips

final class AppSmokeTests: XCTestCase {
    @MainActor
    func testAppStartsIdle() {
        let model = AppModel()
        if case .idle = model.phase {
            return
        }
        XCTFail("The app should start idle")
    }
}
