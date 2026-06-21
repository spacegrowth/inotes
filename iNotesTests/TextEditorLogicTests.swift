import XCTest
import CoreGraphics
@testable import iNotes

/// Characterization + edge-case tests for `TextEditorLogic` (the pure,
/// dependency-free editor string logic extracted from the AppKit views).
///
/// Most tests PIN current behavior (they pass). A handful assert the
/// CORRECT/desired behavior where current behavior is wrong; those are
/// marked `// EXPECTED FAIL — bug #N` and map to a suspected bug in the spec.
final class TextEditorLogicTests: XCTestCase {

    // MARK: - Bullet level detection (levels 1-3)

    func testBulletLevel_detectsEachLevel() {
        XCTAssertEqual(TextEditorLogic.bulletLevel(of: "• item"), 1)
        XCTAssertEqual(TextEditorLogic.bulletLevel(of: "    ◦ item"), 2)
        XCTAssertEqual(TextEditorLogic.bulletLevel(of: "        ▪ item"), 3)
    }

    func testBulletLevel_nonBulletIsZero() {
        XCTAssertEqual(TextEditorLogic.bulletLevel(of: "plain text"), 0)
        XCTAssertEqual(TextEditorLogic.bulletLevel(of: ""), 0)
        XCTAssertEqual(TextEditorLogic.bulletLevel(of: "    indented but no marker"), 0)
    }

    func testBulletLevel_deepestMatchWins() {
        // Level-3 prefix begins with 8 spaces; must not be mis-read as a
        // shallower level. Reversed iteration should return 3, not 2/1.
        XCTAssertEqual(TextEditorLogic.bulletLevel(of: "        ▪ deep"), 3)
        XCTAssertEqual(TextEditorLogic.bulletLevel(of: "    ◦ mid"), 2)
    }

    func testBulletLevel_markerWithoutTrailingSpace_requiresSpace() {
        // FIXED — bug #4: bulletLevel and isBulletParagraph now agree. Both
        // require the trailing space, so a bare marker with no space is NOT a
        // bullet line.
        XCTAssertEqual(TextEditorLogic.bulletLevel(of: "•nospacetext"), 0)
        XCTAssertFalse(TextEditorLogic.isBulletParagraph("•nospacetext"))
    }

    // MARK: - Bullet prefixes & prefix-length math (tab / backtab)

    func testBulletPrefix_exactStrings() {
        XCTAssertEqual(TextEditorLogic.bulletPrefix(for: 1), "• ")
        XCTAssertEqual(TextEditorLogic.bulletPrefix(for: 2), "    ◦ ")
        XCTAssertEqual(TextEditorLogic.bulletPrefix(for: 3), "        ▪ ")
        XCTAssertEqual(TextEditorLogic.bulletPrefix(for: 0), "")
        XCTAssertEqual(TextEditorLogic.bulletPrefix(for: 4), "")
    }

    func testBulletPrefixLength_matchesUTF16LengthOfPrefix() {
        // The length must be in UTF-16 code units because it feeds NSRange /
        // replaceCharacters. Confirm it equals the NSString length of the prefix.
        for level in 1...3 {
            let prefix = TextEditorLogic.bulletPrefix(for: level)
            let expectedUTF16 = (prefix as NSString).length
            XCTAssertEqual(TextEditorLogic.bulletPrefixLength(of: "anything", level: level),
                           expectedUTF16,
                           "level \(level) prefix length must be UTF-16 units")
        }
    }

    func testBulletPrefixLength_isContentIndependent_multiByte() {
        // Bug #1 (mixed counting units) probe: include a multi-byte / emoji line.
        // The extracted helper ignores paraText, so length stays fixed regardless
        // of content — UTF-16-correct here. (Refutes bug #1 in the PURE layer;
        // the surrogate-pair risk remains in the view-layer range math.)
        let emojiLine = "• 👍🏽 family 👨‍👩‍👧‍👦 emoji"
        XCTAssertEqual(TextEditorLogic.bulletPrefixLength(of: emojiLine, level: 1), 2)
        let deepEmoji = "        ▪ 𝕬 astral plane 🧬"
        XCTAssertEqual(TextEditorLogic.bulletPrefixLength(of: deepEmoji, level: 3), 10)
    }

    func testTabMath_indentDeltaIsConstant() {
        // insertTab replaces the level-N prefix with the level-(N+1) prefix and
        // shifts the cursor by (newLen - oldLen). Pin that delta.
        let old1 = TextEditorLogic.bulletPrefixLength(of: "• x", level: 1)
        let new2 = (TextEditorLogic.bulletPrefix(for: 2) as NSString).length
        XCTAssertEqual(new2 - old1, 4) // "• " (2) -> "    ◦ " (6)

        let old2 = TextEditorLogic.bulletPrefixLength(of: "    ◦ x", level: 2)
        let new3 = (TextEditorLogic.bulletPrefix(for: 3) as NSString).length
        XCTAssertEqual(new3 - old2, 4) // "    ◦ " (6) -> "        ▪ " (10)
    }

    func testBacktabMath_outdentDeltaIsConstant() {
        let old3 = TextEditorLogic.bulletPrefixLength(of: "        ▪ x", level: 3)
        let new2 = (TextEditorLogic.bulletPrefix(for: 2) as NSString).length
        XCTAssertEqual(new2 - old3, -4) // 10 -> 6

        let old2 = TextEditorLogic.bulletPrefixLength(of: "    ◦ x", level: 2)
        let new1 = (TextEditorLogic.bulletPrefix(for: 1) as NSString).length
        XCTAssertEqual(new1 - old2, -4) // 6 -> 2
    }

    // MARK: - Bullet add/remove (multiline)

    func testBulletAddRemove_roundTrips() {
        let input = "alpha\nbeta\ngamma"
        let bulleted = TextEditorLogic.addBulletPrefix(toMultilineText: input)
        XCTAssertEqual(bulleted, "• alpha\n• beta\n• gamma")
        XCTAssertEqual(TextEditorLogic.removeBulletPrefix(fromMultilineText: bulleted), input)
    }

    func testBulletAdd_preservesEmptyLines() {
        let input = "alpha\n\ngamma"
        XCTAssertEqual(TextEditorLogic.addBulletPrefix(toMultilineText: input),
                       "• alpha\n\n• gamma")
    }

    func testBulletRemove_handlesMixedLevels() {
        let input = "• one\n    ◦ two\n        ▪ three"
        XCTAssertEqual(TextEditorLogic.removeBulletPrefix(fromMultilineText: input),
                       "one\ntwo\nthree")
    }

    func testBulletAdd_isIdempotent() {
        // FIXED — bug #3: re-applying the bullet prefix is a no-op on a line that
        // already carries one (no more "• • x").
        let once = TextEditorLogic.addBulletPrefix(toMultilineText: "x")
        XCTAssertEqual(once, "• x")
        XCTAssertEqual(TextEditorLogic.addBulletPrefix(toMultilineText: once), "• x")
    }

    // MARK: - Todo add/remove idempotency

    func testTodoAddRemove_roundTrips() {
        let input = "buy milk\nwalk dog"
        let todod = TextEditorLogic.addTodoPrefix(toMultilineText: input)
        XCTAssertEqual(todod, "☐ buy milk\n☐ walk dog")
        XCTAssertEqual(TextEditorLogic.removeTodoPrefix(fromMultilineText: todod), input)
    }

    func testTodoRemove_handlesCheckedAndUnchecked() {
        let input = "☑ done item\n☐ pending item"
        XCTAssertEqual(TextEditorLogic.removeTodoPrefix(fromMultilineText: input),
                       "done item\npending item")
    }

    func testTodoRemove_isIdempotent() {
        // Removing twice is safe: second pass is a no-op (no prefix present).
        let removedOnce = TextEditorLogic.removeTodoPrefix(fromMultilineText: "☐ a\n☐ b")
        XCTAssertEqual(TextEditorLogic.removeTodoPrefix(fromMultilineText: removedOnce),
                       removedOnce)
    }

    func testTodoAdd_isIdempotent() {
        // FIXED — bug #3: re-applying the todo prefix is a no-op on a line that
        // already carries one (no more "☐ ☐ task").
        let once = TextEditorLogic.addTodoPrefix(toMultilineText: "task")
        XCTAssertEqual(once, "☐ task")
        XCTAssertEqual(TextEditorLogic.addTodoPrefix(toMultilineText: once), "☐ task")
    }

    func testTodoAdd_preservesEmptyLines() {
        XCTAssertEqual(TextEditorLogic.addTodoPrefix(toMultilineText: "a\n\nb"),
                       "☐ a\n\n☐ b")
    }

    // MARK: - Auto-bullet on "- "

    func testDashToBullet_firesForFreshDash() {
        XCTAssertTrue(TextEditorLogic.shouldConvertDashToBullet("- "))
    }

    func testDashToBullet_ignoresNonDashLines() {
        XCTAssertFalse(TextEditorLogic.shouldConvertDashToBullet("text"))
        XCTAssertFalse(TextEditorLogic.shouldConvertDashToBullet("-no space"))
    }

    func testDashToBullet_doesNotFireOnAlreadyTypedLine() {
        // FIXED — bug #1: auto-bullet now fires only for a freshly-started "- "
        // line, not on any line that merely starts with "- ". Typing a space on
        // an existing "- alpha" line no longer converts the leading dash.
        XCTAssertFalse(TextEditorLogic.shouldConvertDashToBullet("- alpha "),
                       "should not re-fire on a line that already has content")
        XCTAssertFalse(TextEditorLogic.shouldConvertDashToBullet("- alpha"),
                       "non-empty content after the dash must not convert")
    }

    // MARK: - Heading detection by font size (boundaries)

    func testHeadingLevel_appSizesRoundTripCleanly() {
        // The app's own heading sizes must map back to their level (bug #5 probe).
        XCTAssertEqual(TextEditorLogic.headingLevel(forFontSize: 22), 1) // h1
        XCTAssertEqual(TextEditorLogic.headingLevel(forFontSize: 18), 2) // h2
        XCTAssertEqual(TextEditorLogic.headingLevel(forFontSize: 15), 3) // h3
        XCTAssertEqual(TextEditorLogic.headingLevel(forFontSize: 13), 0) // body
    }

    func testHeadingLevel_boundaryValues() {
        XCTAssertEqual(TextEditorLogic.headingLevel(forFontSize: 20), 1)
        XCTAssertEqual(TextEditorLogic.headingLevel(forFontSize: 19.99), 2)
        XCTAssertEqual(TextEditorLogic.headingLevel(forFontSize: 16), 2)
        XCTAssertEqual(TextEditorLogic.headingLevel(forFontSize: 15.99), 3)
        XCTAssertEqual(TextEditorLogic.headingLevel(forFontSize: 14.5), 3)
        XCTAssertEqual(TextEditorLogic.headingLevel(forFontSize: 14.49), 0)
        XCTAssertEqual(TextEditorLogic.headingLevel(forFontSize: 0), 0)
    }

    func testHeadingLevel_arbitrarySizesAreQuantized() {
        // CHARACTERIZATION of bug #5 lossiness: a non-app size (e.g. 21pt pasted
        // text) is bucketed to h1. Re-applying the heading would resize 21 -> 22,
        // so size-threshold detection is not a clean inverse for arbitrary sizes.
        XCTAssertEqual(TextEditorLogic.headingLevel(forFontSize: 21), 1)
        XCTAssertEqual(TextEditorLogic.headingLevel(forFontSize: 17), 2)
    }
}
