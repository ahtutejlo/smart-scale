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

extension Int {
    var daysText: String {
        let lastTwo = self % 100
        let word = switch self % 10 {
        case 1 where lastTwo != 11: "день"
        case 2...4 where !(12...14).contains(lastTwo): "дні"
        default: "днів"
        }
        return "\(self) \(word)"
    }
}

extension Date {
    var dayAndTime: String {
        let calendar = Calendar.current
        let time = formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(self) { return "Сьогодні, \(time)" }
        if calendar.isDateInYesterday(self) { return "Вчора, \(time)" }
        if calendar.isDate(self, equalTo: .now, toGranularity: .year) {
            return "\(formatted(.dateTime.day().month(.abbreviated))), \(time)"
        }
        return formatted(date: .abbreviated, time: .shortened)
    }

    var shortDay: String {
        Calendar.current.isDateInToday(self) ? "Сьогодні" : formatted(.dateTime.day().month(.abbreviated))
    }
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

extension Norm.Tone {
    var color: Color {
        switch self {
        case .good: Color(.systemGreen)
        case .warning: Color(.systemOrange)
        case .neutral: Color(.secondaryLabel)
        }
    }
}

struct NormChip: View {
    let norm: Norm

    var body: some View {
        Text(norm.label)
            .font(.caption.weight(.medium))
            .foregroundStyle(norm.tone.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(norm.tone.color.opacity(0.15), in: .capsule)
    }
}

struct FatLeanBar: View {
    let fatKg: Double
    let leanKg: Double

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(ChartPalette.secondary)
                    .frame(width: max(0, proxy.size.width - 2) * fatKg / max(fatKg + leanKg, 0.01))
                RoundedRectangle(cornerRadius: 4)
                    .fill(ChartPalette.primary)
            }
        }
        .accessibilityHidden(true)
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
