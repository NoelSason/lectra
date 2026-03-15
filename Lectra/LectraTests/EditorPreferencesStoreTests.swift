import XCTest
@testable import Lectra

final class EditorPreferencesStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: EditorPreferencesStore!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "EditorPreferencesStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = EditorPreferencesStore(defaults: defaults, ubiquitousStore: nil)
    }

    override func tearDown() {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        store = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testPreferencesRoundTripPersistsHighlighterAndDockProfiles() {
        var preferences = EditorPreferences()
        preferences.noteSelectedTool(.highlighter)
        preferences.selectedTool = .hand
        preferences.selectedColor = .yellow
        preferences.highlighterOpacity = 0.52
        preferences.setDockEdge(.left, for: .portraitCompact)
        preferences.setDockEdge(.bottom, for: .landscapeRegular)

        store.save(preferences)
        let loaded = store.load()

        XCTAssertEqual(loaded.selectedTool, .hand)
        XCTAssertEqual(loaded.lastAnnotationTool, .highlighter)
        XCTAssertEqual(loaded.selectedColor, .yellow)
        XCTAssertEqual(loaded.highlighterOpacity, 0.52, accuracy: 0.001)
        XCTAssertEqual(loaded.dockEdge(for: .portraitCompact), .left)
        XCTAssertEqual(loaded.dockEdge(for: .landscapeRegular), .bottom)
    }

    func testDockEdgeFallsBackToLegacyValueWhenProfileSpecificEdgeIsMissing() {
        let preferences = EditorPreferences(toolbarDockEdge: EditorToolbarDockEdge.top.rawValue)

        XCTAssertEqual(preferences.dockEdge(for: .portraitRegular), .top)
        XCTAssertEqual(preferences.dockEdge(for: .landscapeCompact), .top)
    }
}
