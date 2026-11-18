import SwiftUI
import UIKit

/// Signage Sprint design system: ink type, one chrome-yellow "sign" per screen,
/// completion blue for anything done.
enum AppTheme {
    static let ink = Color(red: 0.067, green: 0.094, blue: 0.153)        // #111827
    static let sign = Color(red: 0.973, green: 0.851, blue: 0.400)       // #F8D966
    static let done = Color(red: 0.290, green: 0.424, blue: 0.961)       // #4A6CF5
    static let paper = Color.white
    static let muted = Color(red: 0.373, green: 0.400, blue: 0.463)      // #5F6676
    static let hair = Color(red: 0.851, green: 0.863, blue: 0.894)       // #D9DCE4
    static let disabled = Color(red: 0.604, green: 0.627, blue: 0.675)   // #9AA0AC
    static let disabledFill = Color(red: 0.953, green: 0.957, blue: 0.965)
    static let inkSoft = Color(red: 0.294, green: 0.322, blue: 0.388)    // #4B5263
    static let inkMuted = Color(red: 0.682, green: 0.706, blue: 0.761)   // #AEB4C2

    // Kept for any older call sites.
    static let background = paper
    static let navy = ink
    static let coral = sign
    static let voiceRed = ink
    static let card = paper

    static func display(_ size: CGFloat = 44) -> Font { .system(size: size, weight: .heavy) }
    static let label = Font.system(size: 12, weight: .heavy)
    static let eyebrowFont = Font.system(size: 14, weight: .bold)
}

// MARK: - Type

struct DisplayTitle: View {
    let text: String
    var size: CGFloat = 44
    var color: Color = AppTheme.ink

    var body: some View {
        Text(text)
            .font(AppTheme.display(size))
            .tracking(-size * 0.04)
            .lineSpacing(-4)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

struct Eyebrow: View {
    let text: String
    var color: Color = AppTheme.muted

    var body: some View {
        Text(text.uppercased())
            .font(AppTheme.eyebrowFont)
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

struct SignLabel: View {
    let text: String
    var color: Color = AppTheme.ink

    init(_ text: String, color: Color = AppTheme.ink) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(AppTheme.label)
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

// MARK: - Surfaces

struct SignCard: ViewModifier {
    var fill: Color = AppTheme.sign
    var shadow: Color = AppTheme.ink
    var radius: CGFloat = 18
    var offset: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(AppTheme.ink, lineWidth: 2))
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(shadow)
                    .offset(x: offset, y: offset)
            )
            .padding(.trailing, offset)
            .padding(.bottom, offset)
    }
}

extension View {
    func signCard(fill: Color = AppTheme.sign, shadow: Color = AppTheme.ink, radius: CGFloat = 18, offset: CGFloat = 6) -> some View {
        modifier(SignCard(fill: fill, shadow: shadow, radius: radius, offset: offset))
    }

    func signField(height: CGFloat = 58, borderColor: Color = AppTheme.ink) -> some View {
        self
            .padding(.horizontal, 16)
            .frame(minHeight: height)
            .background(AppTheme.paper, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(borderColor, lineWidth: 2))
    }
}

extension View {
    /// Paper ground, no system nav bar, and a solid backdrop behind the status bar
    /// so scrolled content never runs under the clock.
    func signScreen(_ ground: Color = AppTheme.paper) -> some View {
        self
            .background(ground)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                ground.frame(height: 0)
                    .background(ground.ignoresSafeArea(edges: .top))
            }
    }
}

extension View {
    /// Keeps content clear of the floating tab bar (72pt bar + 4pt gap + breathing room).
    func tabBarClearance() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 88)
        }
    }
}

struct InkRule: View {
    var body: some View {
        Rectangle().fill(AppTheme.ink).frame(height: 2)
    }
}

struct HairRule: View {
    var body: some View {
        Rectangle().fill(AppTheme.hair).frame(height: 1)
    }
}

struct SignPill: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .heavy))
            .tracking(0.5)
            .foregroundStyle(AppTheme.ink)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(AppTheme.sign, in: Capsule())
            .overlay(Capsule().strokeBorder(AppTheme.ink, lineWidth: 2))
    }
}

// MARK: - Buttons

struct SignButtonStyle: ButtonStyle {
    enum Kind { case sign, ink, ghost }
    var kind: Kind = .sign
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shadowOffset: CGFloat = (isEnabled && kind != .ghost && !pressed) ? 4 : 0
        configuration.label
            .font(.system(size: 16, weight: .heavy))
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(fill, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(border, lineWidth: 2))
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(kind == .ink ? AppTheme.sign : AppTheme.ink)
                    .offset(x: shadowOffset, y: shadowOffset)
            )
            .offset(x: pressed && isEnabled && kind != .ghost ? 4 : 0, y: pressed && isEnabled && kind != .ghost ? 4 : 0)
            .padding(.trailing, 4)
            .padding(.bottom, 4)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }

    private var fill: Color {
        guard isEnabled else { return AppTheme.disabledFill }
        switch kind {
        case .sign: return AppTheme.sign
        case .ink: return AppTheme.ink
        case .ghost: return AppTheme.paper
        }
    }

    private var foreground: Color {
        guard isEnabled else { return AppTheme.disabled }
        return kind == .ink ? AppTheme.paper : AppTheme.ink
    }

    private var border: Color {
        isEnabled ? AppTheme.ink : Color(red: 0.788, green: 0.804, blue: 0.839)
    }
}

/// Uppercase back control used in place of the system back button.
struct SignBackButton: View {
    let title: String
    var color: Color = AppTheme.ink
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .heavy))
                Text(title.uppercased())
                    .font(.system(size: 14, weight: .heavy))
                    .tracking(1.1)
                    .lineLimit(1)
            }
            .foregroundStyle(color)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to \(title)")
    }
}

struct CheckDot: View {
    let isOn: Bool
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            if isOn {
                Circle().fill(AppTheme.done)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.45, weight: .black))
                    .foregroundStyle(.white)
            } else {
                Circle().strokeBorder(AppTheme.ink, lineWidth: 2)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Swipe back with hidden navigation bars

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
