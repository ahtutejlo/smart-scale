import Foundation
import Testing
@testable import ScaleKit

struct MeasurementSessionTests {
    @Test func assembleReadingFromFullWeighing() throws {
        var session = MeasurementSession()
        session.consumeAll(try Capture.fullWeighing.decodedPackets())
        let finishedAt = try utc("2026-10-04T23:32:30Z")

        let finished = session.finish(at: finishedAt)
        let reading = try #require(finished)

        #expect(reading.date == finishedAt)
        #expect(reading.weightKg == 88.0)
        #expect(reading.impedanceOhm?.rounded(places: 2) == 462.0)
        #expect(reading.algorithm == 0x07)
        #expect(reading.heartRate == 84)
        #expect(reading.leftLegPercent == 53.4, "final balance, not an in-progress one")
        #expect(session.isFinished)
    }

    @Test func scheduleFinishTimerAcrossFullWeighing() throws {
        let packets = try Capture.fullWeighing.decodedPackets()
        let firstStableWeight = try #require(packets.firstIndex { $0.isStableWeight })
        let completingHeartRate = try #require(packets.firstIndex { $0.isHeartRate })
        var session = MeasurementSession()

        let delays = session.consumeAll(packets)

        let expected: [Duration?] = Array(repeating: nil, count: firstStableWeight)
            + Array(repeating: .seconds(6), count: completingHeartRate - firstStableWeight)
            + [.milliseconds(1500)]
            + Array(repeating: nil, count: packets.count - completingHeartRate - 1)
        #expect(delays == expected, "no timer before stable weight, 6 s while incomplete, 1.5 s once on completion, then none")
    }

    @Test func keepFirstStableWeightAndCorrectImpedanceWithIt() throws {
        var session = MeasurementSession()

        session.consumeAll([
            .liveWeight(kg: 88.0, isStable: true, reportsHeartRate: false),
            .liveWeight(kg: 87.6, isStable: true, reportsHeartRate: false),
            .liveWeight(kg: 70.0, isStable: false, reportsHeartRate: false),
            .impedance(raw: 4124, algorithm: 0x07),
        ])
        let finished = session.finish(at: .now)
        let reading = try #require(finished)

        #expect(reading.weightKg == 88.0, "the first stable weight is the measured weight")
        #expect(reading.impedanceOhm?.rounded(places: 2) == 462.0, "raw 4124 corrected for 88.0 kg, not 87.6 or 70.0 kg")
    }

    @Test func ignorePacketsAfterFinish() {
        var session = MeasurementSession()
        session.consumeAll([
            .liveWeight(kg: 88.0, isStable: true, reportsHeartRate: false),
            .impedance(raw: 4124, algorithm: 0x07),
        ])
        #expect(session.finish(at: .now) != nil)

        let delay = session.consume(.liveWeight(kg: 70.0, isStable: true, reportsHeartRate: false))

        #expect(delay == nil, "a finished session must not restart the finish timer")
        #expect(session.liveWeightKg == 88.0, "a finished session must not take new weight")
        #expect(session.finish(at: .now) == nil, "a session hands out its reading only once")
    }

    @Test func finishCutOffWeighingWithWeightOnly() throws {
        var session = MeasurementSession()

        let delays = session.consumeAll(try Capture.cutOffDuringBalance.decodedPackets())
        let finished = session.finish(at: .now)
        let reading = try #require(finished)

        #expect(delays.last == .seconds(6), "an incomplete weighing keeps the 6 s fallback timer")
        #expect(!delays.contains(.milliseconds(1500)), "a weighing without impedance is never complete")
        #expect(reading.weightKg == 88.02)
        #expect(reading.impedanceOhm == nil)
        #expect(reading.algorithm == nil)
        #expect(reading.heartRate == nil)
        #expect(reading.leftLegPercent == nil, "balance never became final")
    }

    @Test func startNoTimerUntilWeightIsStable() {
        var session = MeasurementSession()

        let delays = session.consumeAll([
            .liveWeight(kg: 87.5, isStable: false, reportsHeartRate: true),
            .impedance(raw: 4124, algorithm: 0x07),
            .heartRate(bpm: 84),
            .liveWeight(kg: 88.0, isStable: true, reportsHeartRate: true),
        ])

        #expect(delays == [nil, nil, nil, .milliseconds(1500)])
    }

    @Test func refuseToFinishWithoutStableWeight() {
        var session = MeasurementSession()
        session.consumeAll([.liveWeight(kg: 87.5, isStable: false, reportsHeartRate: true)])

        #expect(session.finish(at: .now) == nil)
        #expect(!session.isFinished, "the session must stay open for a later stable weight")
    }

    @Test func completeWithoutHeartRateWhenScaleDoesNotMeasureIt() throws {
        var session = MeasurementSession()

        let delays = session.consumeAll([
            .liveWeight(kg: 88.0, isStable: true, reportsHeartRate: false),
            .impedance(raw: 4124, algorithm: 0x07),
        ])
        let finished = session.finish(at: .now)
        let reading = try #require(finished)

        #expect(delays == [.seconds(6), .milliseconds(1500)])
        #expect(reading.heartRate == nil)
        #expect(reading.impedanceOhm?.rounded(places: 2) == 462.0)
    }
}
