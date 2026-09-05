import XCTest
@testable import PaperApp

/// The pure half of the update check: reading a release tag as numbers and
/// deciding what the alert has to say. The network half is one request
/// behind the menu item, and stays untested on purpose: a test that calls
/// GitHub would be the background traffic the feature exists to avoid.
final class UpdateCheckTests: XCTestCase {
    // MARK: Reading a version

    func testReadsAPlainVersion() {
        XCTAssertEqual(UpdateVersion("1.2.3"), UpdateVersion("1.2.3"))
        XCTAssertNotNil(UpdateVersion("1.2.3"))
    }

    func testIgnoresTheTagPrefix() {
        XCTAssertEqual(UpdateVersion("v0.1.0"), UpdateVersion("0.1.0"))
    }

    func testComparesAsNumbersNotText() throws {
        let older = try XCTUnwrap(UpdateVersion("0.9.0"))
        let newer = try XCTUnwrap(UpdateVersion("0.10.0"))
        XCTAssertLessThan(older, newer)
    }

    func testFillsInMissingParts() {
        XCTAssertEqual(UpdateVersion("2"), UpdateVersion("2.0.0"))
        XCTAssertEqual(UpdateVersion("2.1"), UpdateVersion("2.1.0"))
    }

    func testDropsAPrereleaseSuffix() {
        XCTAssertEqual(UpdateVersion("1.2.0-beta.1"), UpdateVersion("1.2.0"))
        XCTAssertEqual(UpdateVersion("1.2.0+build7"), UpdateVersion("1.2.0"))
    }

    func testRefusesWhatItCannotRead() {
        XCTAssertNil(UpdateVersion("nightly"))
        XCTAssertNil(UpdateVersion(""))
    }

    // MARK: Deciding the outcome

    func testNewerTagIsAvailable() {
        XCTAssertEqual(
            UpdateCheck.outcome(currentTag: "0.1.0", latestTag: "v0.2.0"),
            .available(latest: "0.2.0", current: "0.1.0")
        )
    }

    func testSameVersionIsCurrent() {
        XCTAssertEqual(
            UpdateCheck.outcome(currentTag: "0.2.0", latestTag: "v0.2.0"),
            .current("0.2.0")
        )
    }

    func testOlderTagIsCurrentNotADowngrade() {
        XCTAssertEqual(
            UpdateCheck.outcome(currentTag: "0.3.0", latestTag: "v0.2.0"),
            .current("0.3.0")
        )
    }

    func testTenthReleaseBeatsNinth() {
        XCTAssertEqual(
            UpdateCheck.outcome(currentTag: "0.9.0", latestTag: "v0.10.0"),
            .available(latest: "0.10.0", current: "0.9.0")
        )
    }

    func testNoTagIsUnknown() {
        XCTAssertEqual(UpdateCheck.outcome(currentTag: "0.1.0", latestTag: nil), .unknown)
    }

    func testUnreadableTagIsUnknown() {
        // A tag we cannot read is not evidence of anything, and guessing at
        // it would mean either a phantom update or a missed one.
        XCTAssertEqual(UpdateCheck.outcome(currentTag: "0.1.0", latestTag: "nightly"), .unknown)
    }

    func testMissingBundleVersionIsUnknown() {
        XCTAssertEqual(UpdateCheck.outcome(currentTag: nil, latestTag: "v0.2.0"), .unknown)
    }
}
