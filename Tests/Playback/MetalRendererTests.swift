import XCTest
@testable import PlexiOS

final class MetalRendererTests: XCTestCase {
    func testRendererCreatesOnDeviceWithMetal() {
        // Simulator may lack GPU; creation can return nil — must not crash
        let renderer = MetalVideoRenderer()
        if renderer == nil {
            // Acceptable on hosts without Metal
            return
        }
        XCTAssertNotNil(renderer)
        renderer?.aspectMode = .fit
        renderer?.aspectMode = .fill
        renderer?.aspectMode = .stretch
    }

    func testAspectModesExist() {
        XCTAssertEqual(VideoAspectMode.allCases.count, 3)
    }
}
