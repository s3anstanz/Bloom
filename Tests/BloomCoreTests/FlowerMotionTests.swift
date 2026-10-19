import BloomCore
import XCTest

final class FlowerMotionTests: XCTestCase {
    private let opened: TimeInterval = 1_000

    private func bloom(petalsShownAfter delay: TimeInterval = 0) -> FlowerTimeline {
        var timeline = FlowerTimeline(entrance: .bloom, opened: opened)
        timeline.petalsShown = opened + delay
        return timeline
    }

    private func frame(_ timeline: FlowerTimeline, at seconds: TimeInterval, reduceMotion: Bool = false) -> FlowerFrame {
        FlowerMotion.frame(timeline, at: opened + seconds, petals: 6, reduceMotion: reduceMotion)
    }

    func testTheBloomStartsHiddenAndSettlesFullyOpen() {
        let timeline = bloom()
        let start = frame(timeline, at: 0)
        XCTAssertEqual(start.discOpacity, 0)
        XCTAssertTrue(start.petals.allSatisfy { $0.opacity == 0 })

        let settled = FlowerMotion.frame(timeline, at: FlowerMotion.endTime(of: timeline, petals: 6), petals: 6, reduceMotion: false)
        XCTAssertEqual(settled.discScale, 1, accuracy: 0.01)
        XCTAssertEqual(settled.tabsOpacity, 1, accuracy: 0.001)
        for petal in settled.petals {
            XCTAssertEqual(petal.scale, 1, accuracy: 0.01)
            XCTAssertEqual(petal.rotation, 0, accuracy: 0.5)
            XCTAssertEqual(petal.opacity, 1, accuracy: 0.001)
            XCTAssertEqual(petal.light, 0, accuracy: 0.001)
            XCTAssertEqual(petal.labelOpacity, 1, accuracy: 0.001)
        }
    }

    func testPetalsUnfurlOneAfterAnotherClockwise() {
        let early = frame(bloom(), at: 0.3)
        let opacities = early.petals.map(\.opacity)
        XCTAssertEqual(opacities, opacities.sorted(by: >), "Each petal should be no further along than the one before it")
        XCTAssertGreaterThan(opacities[0], 0)
        XCTAssertEqual(opacities[5], 0)
    }

    func testPetalsThatArriveLateStartUnfurlingWhenTheyArrive() {
        let late = bloom(petalsShownAfter: 1)
        XCTAssertEqual(frame(late, at: 1).petals[0].opacity, 0)
        XCTAssertGreaterThan(frame(late, at: 1.2).petals[0].opacity, 0)
        XCTAssertEqual(frame(bloom(), at: 1).petals[0].opacity, 1, accuracy: 0.001)
    }

    func testSwitchingFlowersMidBloomKeepsTheGlassOpeningSmoothly() {
        var switched = FlowerTimeline(entrance: .turn, opened: opened + 0.1)
        switched.glassOpened = opened
        let moment = frame(switched, at: 0.15)
        XCTAssertEqual(moment.discScale, frame(bloom(), at: 0.15).discScale, accuracy: 0.0001)
        XCTAssertLessThan(moment.discScale, 0.9)
        XCTAssertTrue(moment.petals.allSatisfy { $0.opacity < 1 }, "The new flower's petals are still turning in")
    }

    func testADropLightsTheChosenPetalAndDimsTheRest() {
        var timeline = bloom()
        timeline.dropped = opened + 2
        timeline.chosen = 2
        let working = frame(timeline, at: 3)
        XCTAssertEqual(working.petals[2].light, 1)
        XCTAssertEqual(working.petals[2].opacity, 1, accuracy: 0.001)
        for (index, petal) in working.petals.enumerated() where index != 2 {
            XCTAssertLessThan(petal.opacity, 0.5)
        }
        XCTAssertEqual(working.fileOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(working.spinnerOpacity, 1, accuracy: 0.001)
        XCTAssertEqual(working.tabsOpacity, 0, accuracy: 0.001)
    }

    private func withChoices(_ timeline: FlowerTimeline, at seconds: TimeInterval, reduceMotion: Bool = false) -> FlowerFrame {
        FlowerMotion.frame(timeline, at: opened + seconds, petals: 6, choices: 3, reduceMotion: reduceMotion)
    }

    func testChoicesStayHiddenUntilTheyOpenThenSettleFullyShown() {
        var timeline = bloom()
        XCTAssertTrue(withChoices(timeline, at: 3).choices.allSatisfy { $0.opacity == 0 && $0.labelOpacity == 0 })

        timeline.choicesOpened = opened + 3
        let opening = withChoices(timeline, at: 3.05)
        XCTAssertGreaterThan(opening.choices[0].opacity, opening.choices[2].opacity, "They open one after another")
        let end = FlowerMotion.endTime(of: timeline, petals: 6, choices: 3)
        XCTAssertGreaterThan(end, opened + 3)
        for choice in FlowerMotion.frame(timeline, at: end, petals: 6, choices: 3, reduceMotion: false).choices {
            XCTAssertEqual(choice.scale, 1, accuracy: 0.01)
            XCTAssertEqual(choice.opacity, 1, accuracy: 0.001)
            XCTAssertEqual(choice.labelOpacity, 1, accuracy: 0.001)
            XCTAssertEqual(choice.light, 0, accuracy: 0.001)
        }
    }

    func testADropOnAChoiceKeepsItLitAndClearsTheOthers() {
        var timeline = bloom()
        timeline.choicesOpened = opened + 2
        timeline.dropped = opened + 3
        timeline.chosen = 0
        timeline.chosenChoice = 1
        let working = withChoices(timeline, at: 4)
        XCTAssertEqual(working.petals[0].light, 1)
        XCTAssertEqual(working.choices[1].light, 1)
        XCTAssertEqual(working.choices[1].opacity, 1, accuracy: 0.001)
        XCTAssertEqual(working.choices[0].opacity, 0, accuracy: 0.001)
        XCTAssertEqual(working.choices[2].opacity, 0, accuracy: 0.001)
    }

    func testLettingGoFoldsOpenChoicesToo() {
        var timeline = bloom()
        timeline.choicesOpened = opened + 2
        timeline.closed = opened + 3
        XCTAssertTrue(withChoices(timeline, at: 3 + FlowerMotion.closeDuration).choices.allSatisfy { $0.opacity < 0.001 })
    }

    func testWithReduceMotionChoicesOnlyFadeIn() {
        var timeline = bloom()
        timeline.choicesOpened = opened + 2
        for seconds in stride(from: 2.0, through: 3.0, by: 0.02) {
            XCTAssertTrue(withChoices(timeline, at: seconds, reduceMotion: true).choices.allSatisfy { $0.scale == 1 && $0.labelInset == 0 })
        }
        XCTAssertEqual(withChoices(timeline, at: 3, reduceMotion: true).choices[2].opacity, 1)
    }

    func testSuccessReplacesTheSpinnerWithADrawnCheck() {
        var timeline = bloom()
        timeline.dropped = opened + 2
        timeline.finish(succeeded: true, at: opened + 3)
        let done = frame(timeline, at: 4)
        XCTAssertEqual(done.checkOpacity, 1, accuracy: 0.001)
        XCTAssertEqual(done.checkTrim, 1, accuracy: 0.001)
        XCTAssertEqual(done.spinnerOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(done.warningOpacity, 0)
    }

    func testAnInstantResultStillLetsTheDropPlayFirst() {
        var timeline = bloom()
        timeline.dropped = opened + 2
        timeline.finish(succeeded: true, at: opened + 2.01)
        XCTAssertEqual(frame(timeline, at: 2.05).checkOpacity, 0)
        XCTAssertEqual(frame(timeline, at: 4).checkOpacity, 1, accuracy: 0.001)
    }

    func testAFailureShakesThenShowsTheWarningWithTheColourDrained() {
        var timeline = bloom()
        timeline.dropped = opened + 2
        timeline.finish(succeeded: false, at: opened + 3)
        XCTAssertNotEqual(frame(timeline, at: 3.05).shake, 0)
        let settled = frame(timeline, at: 4)
        XCTAssertEqual(settled.shake, 0)
        XCTAssertEqual(settled.warningOpacity, 1, accuracy: 0.001)
        XCTAssertEqual(settled.checkOpacity, 0)
        XCTAssertLessThan(settled.saturation, 0.3)
    }

    func testLettingGoFoldsEverythingAwayQuickly() {
        var timeline = bloom()
        timeline.closed = opened + 2
        let gone = frame(timeline, at: 2 + FlowerMotion.closeDuration)
        XCTAssertLessThanOrEqual(FlowerMotion.closeDuration, 0.5)
        XCTAssertEqual(gone.discOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(gone.pistilOpacity, 0, accuracy: 0.001)
        XCTAssertTrue(gone.petals.allSatisfy { $0.opacity < 0.001 })
    }

    func testReduceMotionOnlyFades() {
        for timeline in sampleTimelines() {
            for seconds in stride(from: 0.0, through: 6.0, by: 0.05) {
                let still = frame(timeline, at: seconds, reduceMotion: true)
                XCTAssertEqual(still.discScale, 1)
                XCTAssertEqual(still.pistilScale, 1)
                XCTAssertEqual(still.shake, 0)
                XCTAssertEqual(still.haloOpacity, 0)
                XCTAssertEqual(still.glintOpacity, 0)
                XCTAssertEqual(still.pulseOpacity, 0)
                XCTAssertEqual(still.warningScale, 1)
                XCTAssertEqual(still.checkTrim, 1)
                for petal in still.petals {
                    XCTAssertEqual(petal.scale, 1)
                    XCTAssertEqual(petal.rotation, 0)
                    XCTAssertEqual(petal.labelInset, 0)
                }
            }
        }
    }

    func testTheFlowerIsAtRestByItsEndTime() {
        for timeline in sampleTimelines() {
            let end = FlowerMotion.endTime(of: timeline, petals: 6)
            let atEnd = FlowerMotion.frame(timeline, at: end, petals: 6, reduceMotion: false)
            let later = FlowerMotion.frame(timeline, at: end + 5, petals: 6, reduceMotion: false)
            let pairs: [(Double, Double)] = [
                (atEnd.discScale, later.discScale),
                (atEnd.discOpacity, later.discOpacity),
                (atEnd.haloOpacity, later.haloOpacity),
                (atEnd.glintOpacity, later.glintOpacity),
                (atEnd.pistilScale, later.pistilScale),
                (atEnd.pistilOpacity, later.pistilOpacity),
                (atEnd.ringTrim, later.ringTrim),
                (atEnd.pulseOpacity, later.pulseOpacity),
                (atEnd.fileOpacity, later.fileOpacity),
                (atEnd.spinnerOpacity, later.spinnerOpacity),
                (atEnd.checkOpacity, later.checkOpacity),
                (atEnd.checkTrim, later.checkTrim),
                (atEnd.warningOpacity, later.warningOpacity),
                (atEnd.warningScale, later.warningScale),
                (atEnd.saturation, later.saturation),
                (atEnd.shake, later.shake),
                (atEnd.tabsOpacity, later.tabsOpacity),
            ]
            for (now, rest) in pairs {
                XCTAssertEqual(now, rest, accuracy: 0.01)
            }
            for (now, rest) in zip(atEnd.petals, later.petals) {
                XCTAssertEqual(now.scale, rest.scale, accuracy: 0.01)
                XCTAssertEqual(now.rotation, rest.rotation, accuracy: 0.5)
                XCTAssertEqual(now.opacity, rest.opacity, accuracy: 0.01)
                XCTAssertEqual(now.light, rest.light, accuracy: 0.01)
                XCTAssertEqual(now.labelOpacity, rest.labelOpacity, accuracy: 0.01)
            }
        }
    }

    /// A bloom, a flower switch, a success, a failure and a let-go.
    private func sampleTimelines() -> [FlowerTimeline] {
        let turn = FlowerTimeline(entrance: .turn, opened: opened)
        var success = bloom()
        success.dropped = opened + 1.5
        success.chosen = 1
        success.finish(succeeded: true, at: opened + 2.5)
        var failure = bloom()
        failure.dropped = opened + 1.5
        failure.finish(succeeded: false, at: opened + 2.5)
        var letGo = bloom()
        letGo.closed = opened + 0.5
        return [bloom(), turn, success, failure, letGo]
    }
}
