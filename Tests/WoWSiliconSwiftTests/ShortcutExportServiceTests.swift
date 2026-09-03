import XCTest
@testable import WoWSiliconSwift

final class ShortcutExportServiceTests: XCTestCase {
    func testWorkflowContainsSingleRunShellScriptAction() throws {
        let script = "printf 'hello'"
        let data = try ShortcutExportService.workflowData(
            name: "Launch Test Configuration",
            shellScript: script
        )
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any]
        )
        let actions = try XCTUnwrap(plist["WFWorkflowActions"] as? [[String: Any]])
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0]["WFWorkflowActionIdentifier"] as? String, "is.workflow.actions.runshellscript")
        let parameters = try XCTUnwrap(actions[0]["WFWorkflowActionParameters"] as? [String: Any])
        XCTAssertEqual(parameters["WFShellScriptActionShell"] as? String, "/bin/zsh")
        XCTAssertEqual(parameters["WFShellScriptActionScript"] as? String, script)
        XCTAssertEqual(parameters["WFShellScriptActionInputMethod"] as? String, "Arguments")
        XCTAssertEqual(parameters["Shell"] as? String, "/bin/zsh")
        XCTAssertEqual(parameters["Script"] as? String, script)
    }
}
