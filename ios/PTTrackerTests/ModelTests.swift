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

    func testParsesPainAndTurnsExtraDetailsIntoCleanBullets() {
        let result = VoiceLogParser.parse(
            "Um I did three sets of ten with eight pounds my pain was four out of ten and my shoulder felt tight at the top I had to move slower on the last set"
        )

        XCTAssertEqual(result.setsCompleted, 3)
        XCTAssertEqual(result.repsPerSet, 10)
        XCTAssertEqual(result.weightValue, 8)
        XCTAssertEqual(result.painAfter, 4)
        XCTAssertEqual(
            result.noteBullets,
            ["Shoulder felt tight at the top", "Had to move slower on the last set"]
        )
    }

    func testParsesPainWasAtWithoutAddingItToNotes() {
        let result = VoiceLogParser.parse("My pain was at a 5 out of 10")

        XCTAssertEqual(result.painAfter, 5)
        XCTAssertTrue(result.noteBullets.isEmpty)
    }

    func testParsesRecognizerPainWasOutOfVariant() {
        let result = VoiceLogParser.parse("After the exercise my pain was out of 5 out of 10")

        XCTAssertEqual(result.painAfter, 5)
        XCTAssertEqual(result.noteBullets, ["After the exercise"])
    }
}

final class ExerciseLogParseResponseTests: XCTestCase {
    func testRequestIncludesExplicitNullContextFields() throws {
        let item = RoutineItem(
            id: UUID(),
            exercise: Exercise(id: UUID(), name: "Custom exercise"),
            position: 0
        )

        let data = try JSONEncoder().encode(
            ExerciseLogParseRequest(transcript: "I did ten reps.", item: item)
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let exercise = try XCTUnwrap(object["exercise"] as? [String: Any])
        let prescription = try XCTUnwrap(exercise["prescription"] as? [String: Any])

        XCTAssertTrue(exercise["tracking_mode"] is NSNull)
        XCTAssertTrue(prescription["duration_seconds"] is NSNull)
        XCTAssertTrue(prescription["weight_value"] is NSNull)
    }

    func testAmbiguousRemoteFieldsRemainBlank() throws {
        let payload = Data(#"""
        {
          "version": 1,
          "extraction": {
            "sets_completed": null,
            "reps_per_set": null,
            "duration_seconds": null,
            "band_resistance": null,
            "weight_value": null,
            "weight_unit": null,
            "pain_after": null,
            "each_side": null,
            "notes": []
          }
        }
        """#.utf8)

        let response = try JSONDecoder().decode(ExerciseLogParseResponse.self, from: payload)
        let extraction = response.extraction.model(transcript: "I think it was five or seven.")

        XCTAssertNil(extraction.painAfter)
        XCTAssertTrue(extraction.noteBullets.isEmpty)
        XCTAssertFalse(extraction.eachSide)
    }

    func testRemotePainAndNotesMapIntoExistingFormModel() throws {
        let payload = Data(#"""
        {
          "version": 1,
          "extraction": {
            "sets_completed": 3,
            "reps_per_set": 10,
            "duration_seconds": null,
            "band_resistance": null,
            "weight_value": 8,
            "weight_unit": "lb",
            "pain_after": 5,
            "each_side": false,
            "notes": ["Shoulder felt tight at the top"]
          }
        }
        """#.utf8)

        let response = try JSONDecoder().decode(ExerciseLogParseResponse.self, from: payload)
        let extraction = response.extraction.model(transcript: "Completed the exercise.")

        XCTAssertEqual(extraction.setsCompleted, 3)
        XCTAssertEqual(extraction.repsPerSet, 10)
        XCTAssertEqual(extraction.weightValue, 8)
        XCTAssertEqual(extraction.weightUnit, .lb)
        XCTAssertEqual(extraction.painAfter, 5)
        XCTAssertEqual(extraction.noteBullets, ["Shoulder felt tight at the top"])
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
