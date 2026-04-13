import XCTest
@testable import Cursor_Metro

final class TimeBucketTests: XCTestCase {
    func testBucketClassifiesDatesAcrossRanges() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let reference = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 3,
            day: 16,
            hour: 12
        ))!

        let today = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 3, day: 16, hour: 9))!
        let yesterday = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 3, day: 15, hour: 9))!
        let last7Days = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 3, day: 11, hour: 9))!
        let last30Days = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 2, day: 20, hour: 9))!
        let older = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 1, day: 1, hour: 9))!

        XCTAssertEqual(TimeBucket.bucket(for: today, reference: reference, calendar: calendar), .today)
        XCTAssertEqual(TimeBucket.bucket(for: yesterday, reference: reference, calendar: calendar), .yesterday)
        XCTAssertEqual(TimeBucket.bucket(for: last7Days, reference: reference, calendar: calendar), .last7Days)
        XCTAssertEqual(TimeBucket.bucket(for: last30Days, reference: reference, calendar: calendar), .last30Days)
        XCTAssertEqual(TimeBucket.bucket(for: older, reference: reference, calendar: calendar), .older)
    }
}
