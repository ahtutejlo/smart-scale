import Foundation
import Testing
@testable import ScaleKit

struct CompositionCase: Sendable, CustomTestStringConvertible {
    let name: String
    let profile: UserProfile
    let weightKg: Double
    let impedanceOhm: Double
    let expected: BodyComposition

    var testDescription: String { name }
}

struct BodyCompositionTests {
    private static let realUser = UserProfile(heightCm: 180, age: 36, sex: .male, initialWeightKg: 88.0)

    private static func reading(weightKg: Double = 88.0, impedanceOhm: Double? = 462.0, algorithm: UInt8 = 0x07) -> ScaleReading {
        ScaleReading(date: .now, weightKg: weightKg, impedanceOhm: impedanceOhm, algorithm: algorithm)
    }

    @Test("WLA07 regression snapshot against openScale (not a vendor correctness proof)", arguments: [
        CompositionCase(
            name: "real weighing 2026-10-04, male 36 y 180 cm",
            profile: realUser, weightKg: 88.0, impedanceOhm: 462.0,
            expected: BodyComposition(
                bodyFatPercent: 25.2, leanMassKg: 65.82, musclePercent: 71.5, skeletalMusclePercent: 40.3,
                waterPercent: 53.1, proteinPercent: 18.4, boneMassKg: 2.9, visceralFat: 13.5,
                bmrKcal: 1879, metabolicAge: 39
            )
        ),
        CompositionCase(
            name: "female 29 y 165 cm",
            profile: UserProfile(heightCm: 165, age: 29, sex: .female, initialWeightKg: 61.5), weightKg: 61.5, impedanceOhm: 540.0,
            expected: BodyComposition(
                bodyFatPercent: 29.9, leanMassKg: 43.11, musclePercent: 65.5, skeletalMusclePercent: 37.9,
                waterPercent: 49.4, proteinPercent: 16.1, boneMassKg: 2.8, visceralFat: 4.0,
                bmrKcal: 1302, metabolicAge: 31
            )
        ),
        CompositionCase(
            name: "boy 12 y 150 cm",
            profile: UserProfile(heightCm: 150, age: 12, sex: .male, initialWeightKg: 42.0), weightKg: 42.0, impedanceOhm: 600.0,
            expected: BodyComposition(
                bodyFatPercent: 10.1, leanMassKg: 37.76, musclePercent: 85.0, skeletalMusclePercent: 42.2,
                waterPercent: 61.4, proteinPercent: 23.6, boneMassKg: 2.1, visceralFat: 1.0,
                bmrKcal: 1105, metabolicAge: 12
            )
        ),
    ])
    func computeWLA07CompositionMatchingOpenScale(_ input: CompositionCase) throws {
        let composition = try #require(BodyComposition(
            reading: Self.reading(weightKg: input.weightKg, impedanceOhm: input.impedanceOhm),
            profile: input.profile
        ))

        #expect(composition.rounded(places: 2) == input.expected)
    }

    @Test func estimateOnlyFatAndLeanMassForNonWLA07Algorithm() throws {
        let composition = try #require(BodyComposition(reading: Self.reading(algorithm: 0x00), profile: Self.realUser))

        #expect(composition.rounded(places: 2) == BodyComposition(bodyFatPercent: 17.03, leanMassKg: 73.01))
    }

    @Test(arguments: [nil, 0, 10] as [Double?])
    func computeNothingWithoutUsableImpedance(impedanceOhm: Double?) {
        #expect(BodyComposition(reading: Self.reading(impedanceOhm: impedanceOhm), profile: Self.realUser) == nil)
    }
}
