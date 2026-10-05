import Testing
@testable import ScaleKit

struct ImpedanceCase: Sendable, CustomTestStringConvertible {
    let raw: Int
    let weightKg: Double
    let expectedOhm: Double

    var testDescription: String { "raw \(raw) at \(weightKg) kg" }
}

struct ImpedanceTests {
    @Test(arguments: [0, 600, 1499], [50.0, 88.0, 120.0])
    func passRawImpedanceBelow1500ThroughUnchanged(raw: Int, weightKg: Double) {
        #expect(ActiveEraProtocol.impedanceOhm(raw: raw, weightKg: weightKg) == Double(raw))
    }

    @Test(arguments: [
        ImpedanceCase(raw: 1500, weightKg: 88.0, expectedOhm: 24.67),
        ImpedanceCase(raw: 4124, weightKg: 88.0, expectedOhm: 462.0),
        ImpedanceCase(raw: 4934, weightKg: 88.02, expectedOhm: 596.99),
        ImpedanceCase(raw: 4172, weightKg: 88.02, expectedOhm: 469.99),
    ])
    func correctRawImpedanceFrom1500ForBodyWeight(_ input: ImpedanceCase) {
        #expect(ActiveEraProtocol.impedanceOhm(raw: input.raw, weightKg: input.weightKg).rounded(places: 2) == input.expectedOhm)
    }
}
