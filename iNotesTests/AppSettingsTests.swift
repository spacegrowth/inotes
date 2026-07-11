import XCTest
@testable import iNotes

/// Tests for `AppSettings`'s base-font-size clamping and persistence. Uses a
/// private `UserDefaults` suite (not `.standard`) so the tests never read or
/// write real app preferences and can run repeatably.
final class AppSettingsTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "AppSettingsTests.\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - clamp

    func testClamp_belowRange_clampsToMinimum() {
        XCTAssertEqual(AppSettings.clamp(1), AppSettings.fontSizeRange.lowerBound)
        XCTAssertEqual(AppSettings.clamp(9.9), AppSettings.fontSizeRange.lowerBound)
    }

    func testClamp_aboveRange_clampsToMaximum() {
        XCTAssertEqual(AppSettings.clamp(100), AppSettings.fontSizeRange.upperBound)
        XCTAssertEqual(AppSettings.clamp(24.1), AppSettings.fontSizeRange.upperBound)
    }

    func testClamp_withinRange_isUnchanged() {
        XCTAssertEqual(AppSettings.clamp(13), 13)
        XCTAssertEqual(AppSettings.clamp(10), 10, "lower bound is inclusive")
        XCTAssertEqual(AppSettings.clamp(24), 24, "upper bound is inclusive")
    }

    // MARK: - baseFontSize(in:) / setBaseFontSize(_:in:)

    func testBaseFontSize_unset_returnsDefault() {
        XCTAssertEqual(AppSettings.baseFontSize(in: defaults), AppSettings.defaultFontSize)
    }

    func testBaseFontSize_setThenGet_roundTrips() {
        AppSettings.setBaseFontSize(18, in: defaults)
        XCTAssertEqual(AppSettings.baseFontSize(in: defaults), 18)
    }

    func testSetBaseFontSize_clampsOutOfRangeValues() {
        AppSettings.setBaseFontSize(999, in: defaults)
        XCTAssertEqual(AppSettings.baseFontSize(in: defaults), AppSettings.fontSizeRange.upperBound)

        AppSettings.setBaseFontSize(-5, in: defaults)
        XCTAssertEqual(AppSettings.baseFontSize(in: defaults), AppSettings.fontSizeRange.lowerBound)
    }

    func testBaseFontSize_toleratesOutOfRangeValueWrittenDirectly() {
        // Simulate a stray/foreign value already sitting in defaults (e.g. a
        // future build with a wider range writing back to an older one).
        defaults.set(999.0, forKey: "editorFontSize")
        XCTAssertEqual(AppSettings.baseFontSize(in: defaults), AppSettings.fontSizeRange.upperBound)
    }
}
