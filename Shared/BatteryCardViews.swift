import SwiftUI

struct ClearGlassCard: ViewModifier {
    var cornerRadius: CGFloat = 22
    var tint: Color? = nil

    /// `glassEffect` does not render reliably in widget extensions (content can vanish).
    private var isAppExtension: Bool {
        Bundle.main.bundleURL.pathExtension == "appex"
    }

    func body(content: Content) -> some View {
        if #available(iOS 26, *), !isAppExtension {
            content
                .glassEffect(
                    glassStyle,
                    in: .rect(cornerRadius: cornerRadius)
                )
        } else {
            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay {
                            if let tint {
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .fill(tint.opacity(0.35))
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                        }
                }
        }
    }

    @available(iOS 26, *)
    private var glassStyle: Glass {
        var glass = Glass.clear
        if let tint {
            glass = glass.tint(tint)
        }
        return glass.interactive()
    }
}

extension View {
    func clearGlassCard(cornerRadius: CGFloat = 22, tint: Color? = nil) -> some View {
        modifier(ClearGlassCard(cornerRadius: cornerRadius, tint: tint))
    }
}

/// Battery card matching the app charging UI. Pass a footer (e.g. slide-to-stop) when needed.
struct BatteryStatusCard<Footer: View>: View {
    let socPercent: Double
    let rangeKm: Double
    let targetSocAC: Int
    let isCharging: Bool
    let chargeSpeedKW: Double
    let chargeTimeText: String?
    var onTapLimit: (() -> Void)? = nil
    var expandsVertically: Bool = false
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Group {
                if let onTapLimit {
                    Button(action: onTapLimit) {
                        metrics
                    }
                    .buttonStyle(.plain)
                } else {
                    metrics
                }
            }

            footer()

            if expandsVertically {
                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(
            maxWidth: expandsVertically ? .infinity : nil,
            maxHeight: expandsVertically ? .infinity : nil,
            alignment: .topLeading
        )
        .foregroundStyle(.white)
        .clearGlassCard()
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: isCharging)
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Battery")
                    .font(.headline)
                Spacer()
                if isCharging {
                    Label {
                        Text(chargePillText)
                    } icon: {
                        Image(systemName: "bolt.fill")
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(MyNiroTheme.green.opacity(0.25), in: Capsule())
                    .foregroundStyle(MyNiroTheme.green)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(socPercent.rounded()))%")
                    .font(.system(size: 40, weight: .bold))
                Spacer()
                Text(VehicleStore.formatKm(rangeKm))
                    .font(.system(size: 40, weight: .bold))
            }

            BatterySOCBar(
                socPercent: socPercent,
                targetSocAC: targetSocAC,
                isCharging: isCharging
            )

            HStack {
                Text(batteryEtaLabel)
                    .font(.footnote)
                    .foregroundStyle(MyNiroTheme.secondaryText)
                    .fixedSize(horizontal: true, vertical: false)
                    .lineLimit(1)
                Spacer()
                Text("Tap to set AC limit")
                    .font(.footnote)
                    .foregroundStyle(MyNiroTheme.tertiaryText)
            }
        }
    }

    private var batteryEtaLabel: String {
        if let charge = chargeTimeText {
            if isCharging {
                return String(format: String(localized: "Full in %@"), charge)
            }
            return String(
                format: String(localized: "Takes %1$@ to %2$lld%%"),
                charge,
                targetSocAC
            )
        }
        return String(format: String(localized: "Limit %lld%% AC"), targetSocAC)
    }

    private var chargePillText: String {
        if chargeSpeedKW > 0 {
            return String(format: String(localized: "Charging · %.1f kW"), chargeSpeedKW)
        }
        return String(localized: "Charging")
    }
}

extension BatteryStatusCard where Footer == EmptyView {
    init(
        socPercent: Double,
        rangeKm: Double,
        targetSocAC: Int,
        isCharging: Bool,
        chargeSpeedKW: Double,
        chargeTimeText: String?,
        onTapLimit: (() -> Void)? = nil,
        expandsVertically: Bool = false
    ) {
        self.socPercent = socPercent
        self.rangeKm = rangeKm
        self.targetSocAC = targetSocAC
        self.isCharging = isCharging
        self.chargeSpeedKW = chargeSpeedKW
        self.chargeTimeText = chargeTimeText
        self.onTapLimit = onTapLimit
        self.expandsVertically = expandsVertically
        self.footer = { EmptyView() }
    }
}

/// SOC track: filled charge, gray remainder to limit, limit slot, and gray tail.
struct BatterySOCBar: View {
    let socPercent: Double
    let targetSocAC: Int
    let isCharging: Bool

    private let barHeight: CGFloat = 10
    private let segmentGap: CGFloat = 4
    private let cycleSeconds: TimeInterval = 1.85

    private var trackHeight: CGFloat {
        barHeight + 20
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isCharging)) { context in
            let phase = isCharging ? Self.phase(at: context.date, cycle: cycleSeconds) : 0
            let glowPulse = 0.55 + 0.45 * abs(sin(phase * .pi * 2))

            GeometryReader { geo in
                let layout = SOCBarLayout(
                    totalWidth: geo.size.width,
                    socPercent: socPercent,
                    limitPercent: Double(targetSocAC),
                    limitSlotWidth: barHeight,
                    gap: segmentGap
                )

                HStack(alignment: .bottom, spacing: segmentGap) {
                    if layout.filledBeforeLimitWidth > 0.5 {
                        SOCBarFilledSegment(
                            width: layout.filledBeforeLimitWidth,
                            height: barHeight,
                            isCharging: isCharging,
                            phase: phase,
                            glowPulse: glowPulse
                        )
                    }

                    if layout.outlineWidth > 0.5 {
                        SOCBarTailSegment(width: layout.outlineWidth, height: barHeight)
                    }

                    SOCLimitMarker(percent: targetSocAC, size: barHeight)

                    if layout.filledAfterLimitWidth > 0.5 {
                        SOCBarFilledSegment(
                            width: layout.filledAfterLimitWidth,
                            height: barHeight,
                            isCharging: false,
                            phase: phase,
                            glowPulse: glowPulse
                        )
                    }

                    if layout.tailWidth > 0.5 {
                        SOCBarTailSegment(width: layout.tailWidth, height: barHeight)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(height: trackHeight)
        .accessibilityHidden(true)
    }

    private static func phase(at date: Date, cycle: TimeInterval) -> CGFloat {
        let t = date.timeIntervalSinceReferenceDate
        return CGFloat(t.truncatingRemainder(dividingBy: cycle) / cycle)
    }
}

private struct SOCBarLayout {
    let filledBeforeLimitWidth: CGFloat
    let outlineWidth: CGFloat
    let filledAfterLimitWidth: CGFloat
    let tailWidth: CGFloat
    let totalWidth: CGFloat

    init(
        totalWidth: CGFloat,
        socPercent: Double,
        limitPercent: Double,
        limitSlotWidth: CGFloat,
        gap: CGFloat
    ) {
        self.totalWidth = totalWidth
        let soc = min(max(socPercent / 100, 0), 1)
        let limit = min(max(limitPercent / 100, 0), 1)

        let filledBeforeLimit = min(soc, limit)
        let outlineSpan = max(limit - soc, 0)
        let filledAfterLimit = max(soc - limit, 0)
        let tailSpan = max(1 - max(soc, limit), 0)

        let showsFilledBeforeLimit = filledBeforeLimit > 0.0001
        let showsOutline = outlineSpan > 0.0001
        let showsFilledAfterLimit = filledAfterLimit > 0.0001
        let showsTail = tailSpan > 0.0001
        let slotCount = (showsFilledBeforeLimit ? 1 : 0)
            + (showsOutline ? 1 : 0)
            + 1
            + (showsFilledAfterLimit ? 1 : 0)
            + (showsTail ? 1 : 0)
        let gapTotal = gap * CGFloat(max(slotCount - 1, 0))
        let available = max(totalWidth - limitSlotWidth - gapTotal, 0)

        filledBeforeLimitWidth = showsFilledBeforeLimit
            ? floor(available * CGFloat(filledBeforeLimit))
            : 0
        outlineWidth = showsOutline ? floor(available * CGFloat(outlineSpan)) : 0
        filledAfterLimitWidth = showsFilledAfterLimit
            ? floor(available * CGFloat(filledAfterLimit))
            : 0
        tailWidth = showsTail
            ? max(available - filledBeforeLimitWidth - outlineWidth - filledAfterLimitWidth, 0)
            : 0
    }
}

private struct SOCLimitMarker: View {
    let percent: Int
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Color.orange)
            .frame(width: size, height: size)
            .shadow(color: Color.orange.opacity(0.45), radius: 3, y: 0)
            .overlay(alignment: .top) {
                Text("\(percent)%")
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
                    .lineLimit(1)
                    .offset(y: -(size + 10))
            }
            .frame(width: size, height: size)
    }
}

private struct SOCBarFilledSegment: View {
    let width: CGFloat
    let height: CGFloat
    let isCharging: Bool
    let phase: CGFloat
    let glowPulse: CGFloat

    var body: some View {
        Capsule()
            .fill(MyNiroTheme.green)
            .frame(width: width, height: height)
            .overlay {
                if isCharging, width > 1 {
                    ChargingFillGlow(phase: phase, glowPulse: glowPulse, barHeight: height)
                }
            }
            .clipShape(Capsule())
            .shadow(
                color: isCharging ? MyNiroTheme.green.opacity(0.35 * glowPulse) : .clear,
                radius: isCharging ? 8 : 0,
                y: 0
            )
    }
}

private struct SOCBarTailSegment: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.12))
            .frame(width: width, height: height)
    }
}

/// Sweeping highlight + tip glow, clipped by the parent capsule fill.
private struct ChargingFillGlow: View {
    let phase: CGFloat
    let glowPulse: CGFloat
    let barHeight: CGFloat

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let band = max(width * 0.42, 28)
            let x = -band + phase * (width + band)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                .white.opacity(0.15),
                                .white.opacity(0.75),
                                MyNiroTheme.green.opacity(0.4),
                                .clear,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: band, height: geo.size.height)
                    .offset(x: x)
                    .blendMode(.plusLighter)

                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    .white.opacity(0.9),
                                    MyNiroTheme.green.opacity(0.55),
                                    .clear,
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: barHeight * 0.95
                            )
                        )
                        .frame(width: barHeight * 1.8, height: barHeight * 1.8)
                        .opacity(0.5 + 0.5 * glowPulse)
                        .offset(x: barHeight * 0.15)
                }
            }
            .frame(width: width, height: geo.size.height)
        }
    }
}
