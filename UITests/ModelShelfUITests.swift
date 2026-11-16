import XCTest

// UI smoke tests per platform. iOS sections are queried by their label, never
// by a tab identifier: on iPad the app shows a NavigationSplitView sidebar and
// on iPhone a tab bar, and both expose the sections as buttons with the
// section title as their label.

#if os(iOS)
final class ModelShelfUITests: XCTestCase {
    private var currentApp: XCUIApplication?

    override func tearDownWithError() throws {
        if let app = currentApp, app.state != .notRunning {
            app.terminate()
            _ = app.wait(for: .notRunning, timeout: 10)
            Thread.sleep(forTimeInterval: 0.25)
        }
        currentApp = nil
        try super.tearDownWithError()
    }

    private func launch(tab: Int) -> XCUIApplication {
        let app = XCUIApplication()
        if app.state != .notRunning {
            app.terminate()
            _ = app.wait(for: .notRunning, timeout: 10)
            Thread.sleep(forTimeInterval: 0.25)
        }
        app.launchArguments = ["-demo", "-tab=\(tab)", "-cfg=demo=1|tab=\(tab)"]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 20)
        currentApp = app
        return app
    }

    func testTabsExistByLabel() throws {
        let app = launch(tab: 0)
        XCTAssertTrue(app.buttons["Library"].firstMatch.waitForExistence(timeout: 15), "missing Library section")
        XCTAssertTrue(app.buttons["Settings"].firstMatch.waitForExistence(timeout: 15), "missing Settings section")
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(app.descendants(matching: .any)["sidebar"].firstMatch.waitForExistence(timeout: 10),
                          "expected NavigationSplitView sidebar on iPad")
        } else {
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10),
                          "expected TabView on compact iPhone width")
        }
    }

    func testLibraryShowsDemoModelsWithBadges() throws {
        let app = launch(tab: 0)
        XCTAssertTrue(app.descendants(matching: .any)["library.list"].firstMatch.waitForExistence(timeout: 15))
        for name in ["tiny-q4k.gguf", "tiny-q8.gguf", "tiny-f16.safetensors", "tiny-bf16.safetensors", "corrupt.gguf"] {
            XCTAssertTrue(app.descendants(matching: .any)["model.row.\(name)"].firstMatch.waitForExistence(timeout: 10),
                          "missing row \(name)")
        }
        XCTAssertTrue(app.descendants(matching: .any)["badge.fits"].firstMatch.waitForExistence(timeout: 10), "expected a fits badge")
        XCTAssertTrue(app.staticTexts["Unreadable"].firstMatch.waitForExistence(timeout: 10), "expected an unreadable badge")
    }

    func testModelDetailShowsHeaderFacts() throws {
        let app = launch(tab: 0)
        let row = app.descendants(matching: .any)["model.row.tiny-q4k.gguf"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.title"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["detail.size"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["detail.tensors"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["detail.quantization"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["detail.ram"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["detail.deviceRAM"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["detail.badgeRow"].firstMatch.waitForExistence(timeout: 10))
        // Notes/Tags sections may be below the fold in the scrollable Form on compact screens.
        let notes = app.descendants(matching: .any)["detail.notes"].firstMatch
        let tags = app.descendants(matching: .any)["detail.tags"].firstMatch
        for _ in 0..<4 where !notes.exists {
            app.swipeUp()
        }
        XCTAssertTrue(notes.waitForExistence(timeout: 10), "missing Notes field")
        for _ in 0..<3 where !tags.exists {
            app.swipeUp()
        }
        XCTAssertTrue(tags.waitForExistence(timeout: 10), "missing Tags field")
    }

    func testSettingsTabShowsAboutAndDevice() throws {
        let app = launch(tab: 0)
        let settingsButton = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 15))
        settingsButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.about"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["settings.deviceRAM"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["settings.loadDemo"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["settings.reset"].firstMatch.waitForExistence(timeout: 10))
    }

    func testTabLaunchArgumentSelectsInitialTab() throws {
        let app = launch(tab: 1)
        XCTAssertTrue(app.descendants(matching: .any)["settings.about"].firstMatch.waitForExistence(timeout: 15),
                      "-tab=1 should open the Settings tab directly")
    }
}

/// Attaches to an already-launched ModelShelf process (`-resetData -seedScreenshots`)
/// and navigates to each of the 5 App Store showcase screens without terminating on teardown,
/// so synchronous foreground `xcrun simctl io <id> screenshot` captures the exact screen.
@MainActor
final class ModelShelfScreenshotUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication(bundleIdentifier: "fr.dcreations.modelshelf")
        app.activate()
        _ = app.wait(for: .runningForeground, timeout: 15)
    }

    private func revealSidebarIfNeeded() {
        guard UIDevice.current.userInterfaceIdiom == .pad, !app.tabBars.firstMatch.exists else { return }
        let sidebarLib = app.descendants(matching: .any)["sidebar.Library"].firstMatch
        if sidebarLib.waitForExistence(timeout: 2), sidebarLib.isHittable { return }
        let togglePred = NSPredicate(
            format: "identifier == 'ToggleSidebar' OR identifier == 'SidebarButton' OR label CONTAINS[c] 'Sidebar'"
        )
        let toggle = app.navigationBars.buttons.matching(togglePred).firstMatch
        if toggle.waitForExistence(timeout: 2), toggle.isHittable {
            toggle.tap()
            Thread.sleep(forTimeInterval: 0.4)
        }
    }

    private func openLibrary() {
        // Pop detail push if currently inside ModelDetailView
        let backPred = NSPredicate(
            format: "identifier == 'BackButton' OR label == 'Back' OR label == 'Model Shelf'"
        )
        let backBtn = app.navigationBars.buttons.matching(backPred).firstMatch
        if backBtn.exists && backBtn.isHittable {
            backBtn.tap()
            Thread.sleep(forTimeInterval: 0.4)
        }
        if UIDevice.current.userInterfaceIdiom == .phone || app.tabBars.firstMatch.exists {
            let tabBtn = app.tabBars.buttons["Library"].firstMatch
            if tabBtn.waitForExistence(timeout: 10), tabBtn.isHittable {
                tabBtn.tap()
            }
        } else {
            let list = app.descendants(matching: .any)["library.list"].firstMatch
            if !list.exists {
                revealSidebarIfNeeded()
                let setBtn = app.descendants(matching: .any)["sidebar.Settings"].firstMatch
                if setBtn.waitForExistence(timeout: 4), setBtn.isHittable {
                    setBtn.tap()
                    Thread.sleep(forTimeInterval: 0.3)
                }
                revealSidebarIfNeeded()
                let libBtn = app.descendants(matching: .any)["sidebar.Library"].firstMatch
                if libBtn.waitForExistence(timeout: 10) {
                    libBtn.tap()
                }
            }
        }
        XCTAssertTrue(app.descendants(matching: .any)["library.list"].firstMatch.waitForExistence(timeout: 15),
                      "Missing library.list")
    }

    private func openModelRow(_ name: String) {
        openLibrary()
        let row = app.descendants(matching: .any)["model.row.\(name)"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Missing model row \(name)")
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.title"].firstMatch.waitForExistence(timeout: 15),
                      "Missing detail.title for \(name)")
    }

    func test1Library() throws {
        openLibrary()
        XCTAssertTrue(app.descendants(matching: .any)["model.row.llama-3.2-3b-instruct-q4_k.gguf"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["badge.fits"].firstMatch.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.6)
    }

    func test2GGUFInspector() throws {
        openModelRow("llama-3.2-3b-instruct-q4_k.gguf")
        XCTAssertTrue(app.descendants(matching: .any)["detail.ram"].firstMatch.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.6)
    }

    func test3SafetensorsInspector() throws {
        openModelRow("flux-1-schnell-bf16.safetensors")
        XCTAssertTrue(app.descendants(matching: .any)["detail.ram"].firstMatch.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.6)
    }

    func test4TensorsAndNotes() throws {
        openLibrary()
        let row = app.descendants(matching: .any)["model.row.qwen2.5-coder-7b-q4_k.gguf"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Missing model row qwen2.5-coder-7b-q4_k.gguf")
        row.tap()
        let notes = app.descendants(matching: .any)["detail.notes"].firstMatch
        let tags = app.descendants(matching: .any)["detail.tags"].firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 15), "Missing detail.notes after scrollToNotes")
        XCTAssertTrue(tags.waitForExistence(timeout: 10), "Missing detail.tags after scrollToNotes")
        Thread.sleep(forTimeInterval: 0.6)
    }

    func test5Settings() throws {
        let backPred = NSPredicate(
            format: "identifier == 'BackButton' OR label == 'Back' OR label == 'Model Shelf'"
        )
        let backBtn = app.navigationBars.buttons.matching(backPred).firstMatch
        if backBtn.exists && backBtn.isHittable {
            backBtn.tap()
            Thread.sleep(forTimeInterval: 0.3)
        }
        if UIDevice.current.userInterfaceIdiom == .phone || app.tabBars.firstMatch.exists {
            let tabBtn = app.tabBars.buttons["Settings"].firstMatch
            XCTAssertTrue(tabBtn.waitForExistence(timeout: 10))
            tabBtn.tap()
        } else {
            revealSidebarIfNeeded()
            let sideBtn = app.descendants(matching: .any)["sidebar.Settings"].firstMatch
            XCTAssertTrue(sideBtn.waitForExistence(timeout: 10))
            sideBtn.tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["settings.about"].firstMatch.waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 0.6)
    }
}
#elseif os(macOS)
final class ModelShelfMacUITests: XCTestCase {
    func testLibraryChromeExists() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-tab=0", "-cfg=demo=1|tab=0"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15), "main window did not open")
        // A toolbar item that does not fit moves into the overflow menu and
        // leaves the accessibility tree, so existence means it is really visible.
        XCTAssertTrue(app.buttons["library.openFolder"].waitForExistence(timeout: 15),
                      "Choose Folder… should be a visible toolbar button")
        XCTAssertTrue(app.buttons["settings.demo"].waitForExistence(timeout: 10),
                      "Demo should be a visible toolbar button")
        // Every text in a row carries the row identifier, hence firstMatch.
        XCTAssertTrue(app.descendants(matching: .any)["model.row.tiny-q4k.gguf"].firstMatch.waitForExistence(timeout: 10),
                      "missing demo row tiny-q4k.gguf")
    }
}
#endif
