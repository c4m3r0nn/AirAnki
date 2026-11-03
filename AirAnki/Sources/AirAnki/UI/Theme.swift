import AirAnkiCore
import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

enum Theme {
    // Shared with the Anki add-on's flash (flash.py) so both surfaces speak the same colours.
    static let again = Color(hex: 0xE5484D)
    static let hard = Color(hex: 0xF5A524)
    static let good = Color(hex: 0x30A46C)
    static let undo = Color(hex: 0x8B8D98)
    static let reveal = Color(hex: 0x6E6AF0)
    static let accent = Color(hex: 0x6366F1)
    static let accentDeep = Color(hex: 0x7C3AED)
    static let warning = Color(hex: 0xF59E0B)
    static let brand = LinearGradient(colors: [Color(hex: 0x4F46E5), Color(hex: 0x8B5CF6)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)

    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static func heading(_ size: CGFloat = 15) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
}

/// What one gesture did, drawn identically in the app, the demo and (in Qt) the Anki flash.
enum ActionStyle: String, Equatable, Sendable {
    case again, hard, good, easy, undo, reveal, unclear

    init?(_ feedback: ActionFeedback) {
        switch feedback {
        case .showedAnswer: self = .reveal
        case .graded(1): self = .again
        case .graded(2): self = .hard
        case .graded(3): self = .good
        case .graded: self = .easy
        case .undone: self = .undo
        case .unclear: self = .unclear
        case .error: return nil
        }
    }

    var color: Color {
        switch self {
        case .again: return Theme.again
        case .hard: return Theme.hard
        case .good, .easy: return Theme.good
        case .undo: return Theme.undo
        case .reveal: return Theme.reveal
        case .unclear: return Theme.warning
        }
    }
    var symbol: String {
        switch self {
        case .again: return "xmark"
        case .hard: return "minus"
        case .good, .easy: return "checkmark"
        case .undo: return "arrow.uturn.backward"
        case .reveal: return "eye.fill"
        case .unclear: return "questionmark"
        }
    }
    var title: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        case .undo: return "Undo"
        case .reveal: return "Show answer"
        case .unclear: return "Try again"
        }
    }
}

/// The three things a user can do with the AirPod.
enum DemoGesture: CaseIterable, Identifiable {
    case right, left, twist
    var id: Self { self }
    var title: String {
        switch self {
        case .right: return "Flick right"
        case .left: return "Flick left"
        case .twist: return "Twist"
        }
    }
    func style(ease: Int) -> ActionStyle {
        switch self {
        case .right: return ease == 3 ? .good : .easy
        case .left: return .again
        case .twist: return .undo
        }
    }
    var calibrationClass: CentroidClass {
        switch self {
        case .right: return .right
        case .left: return .left
        case .twist: return .undo
        }
    }
}

// MARK: - Shared components

struct Panel<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.background.opacity(0.75)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.07)))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}

struct StatusDot: View {
    var color: Color
    var pulsing = false
    @State private var pulse = false
    var body: some View {
        ZStack {
            if pulsing {
                Circle().fill(color.opacity(0.35))
                    .scaleEffect(pulse ? 2.2 : 1).opacity(pulse ? 0 : 1)
                    .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulse)
            }
            Circle().fill(color)
        }
        .frame(width: 8, height: 8)
        .onAppear { pulse = pulsing }
        .onChange(of: pulsing) { _, value in pulse = value }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.heading(14))
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 9)
            .background(Capsule().fill(tint.gradient))
            .shadow(color: tint.opacity(0.35), radius: configuration.isPressed ? 2 : 6, y: configuration.isPressed ? 1 : 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(.primary.opacity(configuration.isPressed ? 0.12 : 0.06)))
            .contentShape(Capsule())
    }
}
