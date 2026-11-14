import SwiftUI

enum CockpitTheme {
    static let accent = Color(red: 0.96, green: 0.20, blue: 0.42)
    static let violet = Color(red: 0.48, green: 0.27, blue: 0.98)
    static let cyan = Color(red: 0.12, green: 0.72, blue: 0.95)

    static func colors(for seed: String) -> [Color] {
        let palettes: [[Color]] = [
            [Color(red: 0.98, green: 0.18, blue: 0.38), Color(red: 0.52, green: 0.16, blue: 0.91)],
            [Color(red: 0.08, green: 0.67, blue: 0.96), Color(red: 0.10, green: 0.86, blue: 0.67)],
            [Color(red: 1.00, green: 0.50, blue: 0.13), Color(red: 0.95, green: 0.15, blue: 0.47)],
            [Color(red: 0.47, green: 0.24, blue: 0.98), Color(red: 0.13, green: 0.55, blue: 1.00)],
            [Color(red: 0.10, green: 0.77, blue: 0.66), Color(red: 0.08, green: 0.39, blue: 0.83)],
            [Color(red: 0.96, green: 0.25, blue: 0.62), Color(red: 0.95, green: 0.60, blue: 0.15)]
        ]
        let value = seed.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
        return palettes[abs(value) % palettes.count]
    }
}

struct CockpitBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            (scheme == .dark ? Color.black : Color(.systemGroupedBackground))
            Circle()
                .fill(CockpitTheme.violet.opacity(scheme == .dark ? 0.26 : 0.12))
                .frame(width: 330, height: 330)
                .blur(radius: 85)
                .offset(x: 150, y: -280)
            Circle()
                .fill(CockpitTheme.accent.opacity(scheme == .dark ? 0.18 : 0.08))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(x: -170, y: 260)
        }
        .ignoresSafeArea()
    }
}

struct ProfileArtwork: View {
    let seed: String
    var symbol = "command"
    var size: CGFloat = 54

    var body: some View {
        let colors = CockpitTheme.colors(for: seed)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .fill(.white.opacity(0.22))
                .frame(width: size * 0.72)
                .blur(radius: size * 0.12)
                .offset(x: size * 0.28, y: -size * 0.25)
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        }
        .frame(width: size, height: size)
        .shadow(color: colors[0].opacity(0.3), radius: size * 0.2, y: size * 0.12)
    }
}

struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.10), radius: 18, y: 9)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }
}

struct SectionHeading: View {
    let title: String
    var caption: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title2.weight(.bold))
            Spacer()
            if let caption { Text(caption).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
        }
    }
}

struct AccountHealthBadge: View {
    let health: AccountHealth
    var compact = false

    private var tint: Color {
        switch health {
        case .healthy: .green
        case .quotaLow, .expiring: .orange
        case .needsLogin, .expired, .quotaCritical: CockpitTheme.accent
        }
    }

    var body: some View {
        Label(compact ? health.compactTitle : health.title, systemImage: health.systemImage)
            .font(.system(size: compact ? 8 : 10, weight: .bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 3 : 4)
            .background(tint.opacity(0.11), in: Capsule())
            .accessibilityLabel("Trạng thái: \(health.title)")
    }
}

struct CapsuleActionStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(tint.opacity(configuration.isPressed ? 0.72 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
