import XCTest
@testable import PTTracker

final class ModelTests: XCTestCase {
    func testHistoryDayHasOnlyCompletePartialAndSkippedStates() {
        let routine = SampleData.routine
        let date = Date()
        let first = routine.routineItems[0]
        let second = routine.routineItems[1]
        let completeLog = ExerciseLog(
            id: UUID(), exerciseID: first.exercise.id, exerciseName: first.exercise.name,
            performedAt: date, setsCompleted: nil, repsPerSet: nil, durationSeconds: 45,
            bandResistance: nil, weightValue: nil, weightUnit: nil, painAfter: nil,
            notes: nil, hasAudio: false
        )
        let partialLog = ExerciseLog(
            id: UUID(), exerciseID: second.exercise.id, exerciseName: second.exercise.name,
            performedAt: date, setsCompleted: 2, repsPerSet: 8, durationSeconds: nil,
            bandResistance: "Red band", weightValue: nil, weightUnit: nil, painAfter: 4,
            notes: "Stopped when the shoulder felt tired.", hasAudio: false
        )

        let snapshot = HistoryDaySnapshot.make(date: date, routine: routine, logs: [completeLog, partialLog])

        XCTAssertEqual(snapshot.status, .partial)
        XCTAssertEqual(snapshot.exercises.map(\.status), [.complete, .partial, .skipped, .skipped])
        XCTAssertEqual(snapshot.exercises[1].result?.performedSummary, "2 × 8 · Red band")
        XCTAssertEqual(snapshot.exercises[1].result?.painAfter, 4)
        XCTAssertEqual(snapshot.exercises[1].result?.notes, "Stopped when the shoulder felt tired.")
        XCTAssertNil(snapshot.exercises[2].result)
    }

    func testHistoryDayIsCompleteOnlyWhenEveryExerciseMeetsItsPrescription() {
        let routine = SampleData.routine
        let date = Date()
        let logs = routine.routineItems.map { item in
            ExerciseLog(
                id: UUID(), exerciseID: item.exercise.id, exerciseName: item.exercise.name,
                performedAt: date, setsCompleted: item.targetSets, repsPerSet: item.targetReps,
                durationSeconds: item.targetDurationSeconds, bandResistance: item.targetBandResistance,
                weightValue: item.targetWeightValue, weightUnit: item.targetWeightUnit,
                painAfter: nil, notes: nil, hasAudio: false
            )
        }

        XCTAssertEqual(HistoryDaySnapshot.make(date: date, routine: routine, logs: logs).status, .complete)
        XCTAssertEqual(HistoryDaySnapshot.make(date: date, routine: routine, logs: []).status, .skipped)
    }

    @MainActor
    func testTodayLogsReturnsEveryMatchingLogNewestFirst() throws {
        let configuration = AppConfiguration(
            supabaseURL: nil,
            supabaseAnonKey: nil,
            useMockData: true,
            authTestPhone: nil,
            authTestCode: nil
        )
        let model = AppModel(configuration: configuration)
        let item = RoutineItem(id: UUID(), exercise: SampleData.standingRow, position: 0)
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let olderDate = try XCTUnwrap(calendar.date(byAdding: .hour, value: 1, to: start))
        let newerDate = try XCTUnwrap(calendar.date(byAdding: .hour, value: 2, to: start))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: start))
        let older = exerciseLog(exercise: item.exercise, performedAt: olderDate)
        let newer = exerciseLog(exercise: item.exercise, performedAt: newerDate)
        let priorDay = exerciseLog(exercise: item.exercise, performedAt: yesterday)
        let anotherExercise = exerciseLog(exercise: SampleData.bridge, performedAt: newerDate)
        model.history = [older, priorDay, anotherExercise, newer]

        XCTAssertEqual(model.todayLogs(for: item).map(\.id), [newer.id, older.id])
        XCTAssertEqual(model.todayLog(for: item)?.id, newer.id)
    }

    @MainActor
    func testConfiguredTestPhoneSkipsSMSRequestAndShowsFixedCode() async throws {
        let phone = "+12025550147"
        let configuration = AppConfiguration(
            supabaseURL: try XCTUnwrap(URL(string: "https://example.supabase.co")),
            supabaseAnonKey: "test-key",
            useMockData: false,
            authTestPhone: phone,
            authTestCode: "123456"
        )
        let model = AppModel(configuration: configuration)

        await model.requestCode(phone: phone)

        XCTAssertEqual(model.authStep, .code(phone: phone))
        XCTAssertEqual(model.testCodeHint(for: phone), "123456")
        XCTAssertNil(model.errorMessage)
    }

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

    private func exerciseLog(exercise: Exercise, performedAt: Date) -> ExerciseLog {
        ExerciseLog(
            id: UUID(),
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            performedAt: performedAt,
            setsCompleted: 2,
            repsPerSet: 8,
            durationSeconds: nil,
            bandResistance: nil,
            weightValue: nil,
            weightUnit: nil,
            painAfter: 1,
            notes: nil,
            hasAudio: false
        )
    }
}

final class RoutineEditTests: XCTestCase {
    private let routine = SampleData.routine

    func testTimedMoveWithSetsAndWeightReadsAsSetsTimesSeconds() {
        var item = routine.routineItems[0]
        var rx = MovePrescription(item: item)
        XCTAssertEqual(rx.count, .time)
        rx.sets = 3
        rx.seconds = 15
        rx.resistance = .weight
        rx.weight = 10
        rx.unit = .lb
        item = rx.applied(to: item)

        XCTAssertEqual(item.shortPrescription, "3 × 15 sec · 10 lb")
        XCTAssertNil(item.targetReps)
        XCTAssertNil(item.targetBandResistance)
        XCTAssertEqual(item.exercise.trackingMode, .duration)
    }

    func testSingleSetTimedMoveStillReadsAsJustTheTime() {
        XCTAssertEqual(MovePrescription(item: routine.routineItems[0]).summary(for: SampleData.bridge), "45 sec")
    }

    func testSwitchingToRepsClearsTimeAndBandSwitchClearsWeight() {
        let start = RoutineItem(id: UUID(), exercise: SampleData.bridge, position: 0, targetSets: 3,
                                targetDurationSeconds: 30, targetWeightValue: 10, targetWeightUnit: .kg)
        var rx = MovePrescription(item: start)
        XCTAssertEqual(rx.resistance, .weight)
        rx.count = .reps
        rx.reps = 12
        rx.resistance = .band
        rx.band = "Blue band"
        let item = rx.applied(to: start)

        XCTAssertEqual(item.shortPrescription, "3 × 12 · Blue band")
        XCTAssertNil(item.targetDurationSeconds)
        XCTAssertNil(item.targetWeightValue)
        XCTAssertNil(item.targetWeightUnit)
        XCTAssertEqual(item.exercise.trackingMode, .reps)
    }

    func testExistingBandNameIsKeptAsAChoice() {
        let item = RoutineItem(id: UUID(), exercise: SampleData.standingRow, position: 0, targetSets: 3,
                               targetReps: 10, targetBandResistance: "Purple loop")
        let rx = MovePrescription(item: item)
        XCTAssertEqual(rx.resistance, .band)
        XCTAssertEqual(rx.bandOptions.last, "Purple loop")
    }

    func testDraftWithoutEditsHasNoChanges() {
        XCTAssertFalse(RoutineEditDraft(routine: routine).hasChanges)
    }

    func testDraftUpdateDropsRemovedMovesRenumbersAndKeepsNewOnes() {
        var draft = RoutineEditDraft(routine: routine)
        let heel = routine.routineItems[2]
        let clam = routine.routineItems[3]
        var rx = MovePrescription(item: heel)
        rx.sets = 3
        rx.reps = 15
        draft.update(moveID: heel.id, prescription: rx)
        draft.setRemoved(true, moveID: clam.id)
        let lift = Exercise(id: UUID(), name: "Side-lying leg lift", trackingMode: .reps)
        draft.add(exercise: lift, prescription: .defaults(for: .reps), isNewExercise: true)
        draft.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        XCTAssertTrue(draft.hasChanges)
        XCTAssertTrue(draft.moves.first { $0.id == heel.id }!.isChanged)
        let update = draft.update()
        XCTAssertEqual(update.items.map(\.exercise.name), ["Heel raise", "Bridge", "Standing row", "Side-lying leg lift"])
        XCTAssertEqual(update.items.map(\.position), [0, 1, 2, 3])
        XCTAssertEqual(update.items[0].shortPrescription, "3 × 15")
        XCTAssertEqual(update.removedItemIDs, [clam.id])
        XCTAssertEqual(update.newExercises.map(\.name), ["Side-lying leg lift"])
        XCTAssertEqual(update.newItemIDs.count, 1)
        XCTAssertTrue(update.trackingModeChanges.isEmpty)
    }

    func testUndoRestoresARemovedMoveAndRemovingANewMoveDropsIt() {
        var draft = RoutineEditDraft(routine: routine)
        let clam = routine.routineItems[3]
        draft.setRemoved(true, moveID: clam.id)
        draft.setRemoved(false, moveID: clam.id)
        XCTAssertFalse(draft.hasChanges)

        let wallSit = Exercise(id: UUID(), name: "Wall sit", trackingMode: .duration)
        draft.add(exercise: wallSit, prescription: .defaults(for: .duration), isNewExercise: true)
        let added = draft.moves.last!.id
        draft.setRemoved(true, moveID: added)
        XCTAssertFalse(draft.moves.contains { $0.id == added })
        XCTAssertTrue(draft.newExercises.isEmpty)
        XCTAssertFalse(draft.hasChanges)
    }

    func testSwitchingAnExistingMoveToTimeRecordsTheTrackingModeChange() {
        var draft = RoutineEditDraft(routine: routine)
        let heel = routine.routineItems[2]
        var rx = MovePrescription(item: heel)
        rx.count = .time
        draft.update(moveID: heel.id, prescription: rx)
        XCTAssertEqual(draft.update().trackingModeChanges, [heel.exercise.id: .duration])
    }

    func testOnlyAPlanDatedTodayIsEditedInPlace() {
        var older = routine
        older.scheduledFor = Calendar.current.date(byAdding: .day, value: -3, to: .now)!
        XCTAssertTrue(RoutineEditDraft(routine: routine).update().editsTodaysRoutine())
        XCTAssertFalse(RoutineEditDraft(routine: older).update().editsTodaysRoutine())
    }

    func testHistoryUsesThePlanInForceOnEachDay() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: today)!
        let tenDaysAgo = calendar.date(byAdding: .day, value: -10, to: today)!
        var oldPlan = routine
        oldPlan.scheduledFor = tenDaysAgo
        var newPlan = routine
        newPlan.scheduledFor = today
        newPlan.routineItems = Array(routine.routineItems.prefix(2))
        let plans = [newPlan, oldPlan]

        XCTAssertEqual(plans.plan(for: threeDaysAgo)?.routineItems.count, 4)
        XCTAssertEqual(plans.plan(for: today)?.routineItems.count, 2)
        XCTAssertEqual(plans.plan(for: .now)?.routineItems.count, 2)
        XCTAssertNil(plans.plan(for: calendar.date(byAdding: .day, value: -20, to: today)!))
    }

    func testMockRepositoryKeepsThePreviousPlanWhenAnOlderPlanIsEdited() async throws {
        let repository = MockPTRepository()
        var current = try await repository.todayRoutine()
        current.scheduledFor = Calendar.current.date(byAdding: .day, value: -5, to: .now)!
        var draft = RoutineEditDraft(routine: current)
        draft.setRemoved(true, moveID: draft.moves[0].id)
        _ = try await repository.saveRoutine(draft.update())
        let month = HistoryMonth.bounds(containing: .now)
        let plans = try await repository.plans(from: month.start, to: month.end)
        XCTAssertEqual(plans.map(\.routineItems.count), [3, 4])
    }

    func testPlanRangeKeepsPlansInsideTheMonthAndTheOneInForceAtItsStart() throws {
        let calendar = Calendar.current
        let month = HistoryMonth.bounds(containing: .now, calendar: calendar)
        func plan(daysFromStart offset: Int) throws -> Routine {
            var routine = SampleData.routine
            routine.scheduledFor = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: month.start))
            return routine
        }
        let veryOld = try plan(daysFromStart: -90)
        let inForceAtStart = try plan(daysFromStart: -10)
        let midMonth = try plan(daysFromStart: 5)
        let nextMonth = try plan(daysFromStart: 45)

        let covering = PlanRange.covering(start: month.start, end: month.end,
                                          in: [veryOld, nextMonth, inForceAtStart, midMonth], calendar: calendar)
        XCTAssertEqual(covering.map(\.scheduledFor), [midMonth.scheduledFor, inForceAtStart.scheduledFor])
    }

    func testHistoryMonthGroupsLogsByLocalDay() throws {
        let calendar = Calendar.current
        let month = HistoryMonth.bounds(containing: .now, calendar: calendar)
        let dayTwo = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: month.start))
        let morning = try XCTUnwrap(calendar.date(byAdding: .hour, value: 8, to: dayTwo))
        let evening = try XCTUnwrap(calendar.date(byAdding: .hour, value: 21, to: dayTwo))
        let otherDay = try XCTUnwrap(calendar.date(byAdding: .hour, value: 10, to: month.start))
        func log(_ date: Date) -> ExerciseLog {
            ExerciseLog(id: UUID(), exerciseID: SampleData.bridge.id, exerciseName: "Bridge", performedAt: date,
                        setsCompleted: nil, repsPerSet: nil, durationSeconds: 45, bandResistance: nil,
                        weightValue: nil, weightUnit: nil, painAfter: nil, notes: nil, hasAudio: false)
        }
        let early = log(morning), late = log(evening), other = log(otherDay)
        let historyMonth = HistoryMonth(start: month.start, logs: [early, other, late], plans: [], calendar: calendar)

        XCTAssertEqual(historyMonth.logs(on: dayTwo, calendar: calendar).map(\.id), [late.id, early.id])
        XCTAssertEqual(historyMonth.logs(on: month.start, calendar: calendar).map(\.id), [other.id])
    }

    func testMockRepositoryOnlyReturnsLogsInsideTheRange() async throws {
        let repository = MockPTRepository()
        let item = SampleData.routine.routineItems[0]
        _ = try await repository.saveLog(ExerciseLogDraft(exercise: item.exercise, routineItemID: item.id, durationSeconds: 45))
        let month = HistoryMonth.bounds(containing: .now)
        let previous = HistoryMonth.bounds(containing: month.start.addingTimeInterval(-1))
        let thisMonth = try await repository.logs(from: month.start, to: month.end)
        let lastMonth = try await repository.logs(from: previous.start, to: previous.end)
        XCTAssertEqual(thisMonth.count, 1)
        XCTAssertTrue(lastMonth.isEmpty)
    }

    func testRemovingEveryMoveLeavesNothingToKeep() {
        var draft = RoutineEditDraft(routine: routine)
        for move in draft.moves { draft.setRemoved(true, moveID: move.id) }
        XCTAssertEqual(draft.keptCount, 0)
    }

    func testMockRepositorySavesTheEditedPlan() async throws {
        let repository = MockPTRepository()
        var draft = RoutineEditDraft(routine: try await repository.todayRoutine())
        draft.setRemoved(true, moveID: draft.moves[0].id)
        let saved = try await repository.saveRoutine(draft.update())
        XCTAssertEqual(saved.routineItems.map(\.exercise.name), ["Standing row", "Heel raise", "Clamshell"])
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

final class TodaysWorkCardTests: XCTestCase {
    func testWeightTakesLastColumnOverBand() {
        let logs = [
            log(sets: 3, reps: 8, band: "Red"),
            log(sets: 3, reps: 10, band: "Red", weight: 12)
        ]
        XCTAssertEqual(TodaysWorkCard.columns(for: logs), [.sets, .reps, .weight])
    }

    func testBandColumnWhenNoWeightLogged() {
        XCTAssertEqual(TodaysWorkCard.columns(for: [log(sets: 2, reps: 10, band: "Green")]), [.sets, .reps, .band])
    }

    func testDurationOnlyLog() {
        XCTAssertEqual(TodaysWorkCard.columns(for: [log(duration: 50)]), [.duration])
        XCTAssertEqual(TodaysWorkCard.columns(for: [log()]), [])
    }

    private func log(sets: Int? = nil, reps: Int? = nil, duration: Int? = nil, band: String? = nil, weight: Double? = nil) -> ExerciseLog {
        ExerciseLog(
            id: UUID(),
            exerciseID: UUID(),
            exerciseName: "Standing row",
            performedAt: .now,
            setsCompleted: sets,
            repsPerSet: reps,
            durationSeconds: duration,
            bandResistance: band,
            weightValue: weight,
            weightUnit: weight == nil ? nil : .lb,
            painAfter: nil,
            notes: nil,
            hasAudio: false
        )
    }
}
