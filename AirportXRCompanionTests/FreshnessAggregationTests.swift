import XCTest
@testable import AirBorder

final class FreshnessAggregationTests: XCTestCase {
    @MainActor
    func testCachedOrStaleLegsAreNeverReportedAsLive() {
        XCTAssertEqual(LongHaulExperienceViewModel.combinedFreshness([.live, .cached]), .cached)
        XCTAssertEqual(LongHaulExperienceViewModel.combinedFreshness([.live, .stale]), .stale)
        XCTAssertEqual(LongHaulExperienceViewModel.combinedFreshness([.live, .live]), .live)
    }
}
