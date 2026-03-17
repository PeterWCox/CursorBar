import XCTest
@testable import Cursor_Metro

final class ProjectSettingsStoreTests: XCTestCase {
    @MainActor
    func testStoreTrimsAndReloadsSettings() throws {
        let workspacePath = try makeWorkspacePath()
        let store = ProjectSettingsStore()

        store.setDebugURL(workspacePath: workspacePath, "  http://localhost:3000/path  ")
        store.setStartupScripts(workspacePath: workspacePath, ["#!/bin/bash\necho hi\n"])

        XCTAssertEqual(store.debugURL(for: workspacePath), "http://localhost:3000/path")
        XCTAssertEqual(store.snapshot(for: workspacePath).startupScripts, ["#!/bin/bash\necho hi"])

        ProjectSettingsStorage.setDebugURL(workspacePath: workspacePath, "  http://localhost:4000  ")
        ProjectSettingsStorage.setStartupScripts(workspacePath: workspacePath, ["npm run dev\n"])

        XCTAssertEqual(store.debugURL(for: workspacePath), "http://localhost:4000")
        XCTAssertEqual(store.snapshot(for: workspacePath).startupScripts, ["npm run dev"])

        store.setDebugURL(workspacePath: workspacePath, "   \n")

        XCTAssertNil(store.debugURL(for: workspacePath))
        XCTAssertEqual(store.snapshot(for: workspacePath).debugURL, "")
    }
}
