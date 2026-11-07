import XCTest
@testable import PTTracker

final class ModelTests: XCTestCase {
    func testPrescriptionSummaryKeepsBandAndWeightSeparate() {
        let item = RoutineItem(
            id: UUID(),
            exercise: SampleData.standingRow,
            position: 0,
            targetSets: 3,
            targetReps: 10,
            targetBandResistance: "Red band",
            targetWeightValue: 12.5,
            targetWeightUnit: .lb
        )

        XCTAssertEqual(item.prescriptionSummary, "3 sets · 10 reps · Red band · 12.5 lb")
    }

    func testExerciseOnlyRequiresNameInTheClientModel() {
        let exercise = Exercise(id: UUID(), name: "Custom exercise")
        XCTAssertEqual(exercise.name, "Custom exercise")
        XCTAssertNil(exercise.trackingMode)
    }
}

final class VoiceLogParserTests: XCTestCase {
    func testParsesRepsWeightAndEachSide() {
        let result = VoiceLogParser.parse("I did three sets of ten each side with 8 pounds")
        XCTAssertEqual(result.setsCompleted, 3)
        XCTAssertEqual(result.repsPerSet, 10)
        XCTAssertEqual(result.weightValue, 8)
        XCTAssertEqual(result.weightUnit, .lb)
        XCTAssertTrue(result.eachSide)
    }

    func testParsesDurationAndBand() {
        let result = VoiceLogParser.parse("Held it for two minutes with a red band")
        XCTAssertEqual(result.durationSeconds, 120)
        XCTAssertEqual(result.bandResistance, "Red band")
    }
}

final class LocalDateKeyTests: XCTestCase {
    func testUsesDeviceDayWhenUTCHasAlreadyAdvanced() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-07T04:12:00Z"))

        XCTAssertEqual(LocalDateKey.string(for: date, calendar: calendar), "2026-11-06")
    }
}
