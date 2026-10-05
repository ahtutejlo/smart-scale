import SwiftUI
import UIKit

enum ChartPalette {
    static let primary = Color(light: 0x2A78D6, dark: 0x3987E5)
    static let secondary = Color(light: 0xEB6834, dark: 0xD95926)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

extension Double {
    func formatted(digits: Int) -> String {
        formatted(.number.precision(.fractionLength(digits)).grouping(.never))
    }

    var kg: String { "\(formatted(digits: 1)) кг" }

    var signedKg: String {
        let sign = self > 0.05 ? "+" : self < -0.05 ? "−" : ""
        return "\(sign)\(abs(self).formatted(digits: 1)) кг"
    }

    var percent: String { "\(formatted(digits: 1)) %" }
}

extension View {
    func cardStyle() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.background.secondary, in: .rect(cornerRadius: 16))
    }
}

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .cardStyle()
    }
}

struct MetricCell: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
    }
}

struct HeroNumber: View {
    let text: String
    @ScaledMetric private var size: CGFloat

    init(_ text: String, size: CGFloat) {
        self.text = text
        _size = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
    }

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
    }
}

struct Explanation: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
