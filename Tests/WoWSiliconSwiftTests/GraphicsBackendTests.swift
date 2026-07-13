import XCTest
@testable import WoWSiliconSwift

final class GraphicsBackendTests: XCTestCase {
    func testD9VKIsDefaultForExistingSettings() throws {
        let settings = try JSONDecoder().decode(GraphicsSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.backend, .d9vk)
        XCTAssertEqual(settings.backend.wineDLLOverride, "d3d9=n")
    }

    func testD9MTUsesBuiltinD3D9() {
        XCTAssertEqual(GraphicsBackend.d9mt.wineDLLOverride, "d3d9=b")
    }
}
