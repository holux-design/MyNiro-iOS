import SwiftUI
import UIKit

struct CarTabView: View {
    @Bindable var store: VehicleStore
    var onOpenSettings: () -> Void = {}
    @State private var showChargeLimit = false
    @State private var showClimate = false
    @State private var scrollOffset: CGFloat = 0
    @State private var cardsHeight: CGFloat = 320
    @State private var isChargeSlideDragging = false

    /// Native asset aspect (1024×399) — frame padding is baked into the image.
    private let carAspect: CGFloat = 1024.0 / 399.0
    private let carHorizontalInset: CGFloat = 28
    /// How far the car sits up over the SOC% at rest (car draws on top).
    private let percentCarOverlap: CGFloat = 18
    /// Extra room below the car before widgets — more scroll over the hero.
    private let heroScrollRoom: CGFloat = 24
    private let percentHeight: CGFloat = 88
    private let collapseDistance: CGFloat = 140
    private let titleExpanded: CGFloat = 34
    private let titleCollapsed: CGFloat = 20
    private let subtitleExpandedHeight: CGFloat = 20
    private let headerTopExpanded: CGFloat = 12
    private let headerBottomExpanded: CGFloat = 8
    /// Gap between collapsed “my Niro” bottom and the first tile top at max scroll.
    private let collapsedHeaderTileSpacing: CGFloat = 12

    /// Percentage drifts slowest; car mid-speed; scroll content at 1×.
    private let percentParallax: CGFloat = 0.18
    private let carParallax: CGFloat = 0.48

    private var collapseProgress: CGFloat {
        min(max(scrollOffset / collapseDistance, 0), 1)
    }

    private var titleScale: CGFloat {
        let ratio = titleCollapsed / titleExpanded
        return 1 - (1 - ratio) * collapseProgress
    }

    private var subtitleOpacity: CGFloat {
        1 - collapseProgress
    }

    private var subtitleHeight: CGFloat {
        subtitleExpandedHeight * (1 - collapseProgress)
    }

    private var headerTopPadding: CGFloat {
        headerTopExpanded - 4 * collapseProgress
    }

    private var headerBottomPadding: CGFloat {
        headerBottomExpanded - 4 * collapseProgress
    }

    /// Fully expanded header — used for scroll content inset (must stay fixed).
    private var expandedHeaderBlockHeight: CGFloat {
        headerTopExpanded + titleExpanded + 4 + subtitleExpandedHeight + headerBottomExpanded
    }

    /// Collapsed sticky header height (subtitle gone, tighter padding).
    private var collapsedHeaderBlockHeight: CGFloat {
        (headerTopExpanded - 4) + titleExpanded + (headerBottomExpanded - 4)
    }

    private var headerBlockHeight: CGFloat {
        headerTopPadding + titleExpanded + 4 + subtitleHeight + headerBottomPadding
    }

    /// Bottom pad so max scroll parks the first tile under the collapsed title.
    private func bottomScrollPadding(viewportHeight: CGFloat) -> CGFloat {
        max(0, viewportHeight - collapsedHeaderBlockHeight - collapsedHeaderTileSpacing - cardsHeight)
    }

    private var socValue: Int {
        Int(store.socPercent.rounded())
    }

    private func carWidth(for width: CGFloat) -> CGFloat {
        max(width - carHorizontalInset * 2, 0)
    }

    private func carHeight(for width: CGFloat) -> CGFloat {
        carWidth(for: width) / carAspect
    }

    private func scrollTopSpacer(for width: CGFloat) -> CGFloat {
        expandedHeaderBlockHeight
            + 4
            + percentHeight
            + carHeight(for: width)
            - percentCarOverlap
            + heroScrollRoom
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .top) {
                MyNiroTheme.background.ignoresSafeArea()

                parallaxHero(width: width)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear
                            .frame(height: scrollTopSpacer(for: width))

                        VStack(alignment: .leading, spacing: 20) {
                            BatteryCard(
                                store: store,
                                scrollDragActive: $isChargeSlideDragging
                            ) {
                                showChargeLimit = true
                            }

                            actionTiles

                            Button(action: onOpenSettings) {
                                HStack(spacing: 6) {
                                    Image(systemName: "gearshape.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Settings")
                                        .font(.caption.weight(.semibold))
                                }
                                .foregroundStyle(MyNiroTheme.secondaryText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.08), in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                            .accessibilityLabel(String(localized: "Settings"))
                        }
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { newHeight in
                            guard abs(newHeight - cardsHeight) > 0.5 else { return }
                            cardsHeight = newHeight
                        }
                        .padding(.top, 20)

                        // Sized so max scroll parks the first tile under collapsed “my Niro”.
                        Color.clear
                            .frame(
                                height: bottomScrollPadding(
                                    viewportHeight: geo.size.height - geo.safeAreaInsets.bottom
                                )
                            )
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
                .scrollDisabled(isChargeSlideDragging)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, newValue in
                    // Keep negative values so rubber-band overscroll (pull-to-refresh)
                    // drives parallax downward; collapseProgress already clamps ≥ 0.
                    guard abs(newValue - scrollOffset) > 0.5 else { return }
                    scrollOffset = newValue
                }

                stickyHeader
            }
        }
        .refreshable {
            await Task { @MainActor in
                await store.refresh(force: true)
            }.value
        }
        .overlay {
            if store.isLoading && store.status == nil {
                ZStack {
                    MyNiroTheme.background.opacity(0.72)
                    VStack(spacing: 14) {
                        ProgressView()
                            .tint(MyNiroTheme.green)
                            .scaleEffect(1.2)
                        Text(store.busyMessage ?? String(localized: "Loading…"))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(MyNiroTheme.secondaryText)
                    }
                }
                .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showChargeLimit) {
            ChargeLimitSheet(store: store)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showClimate) {
            ClimateDefaultsSheet(store: store)
                .presentationDetents([.medium])
        }
    }

    private func parallaxHero(width screenWidth: CGFloat) -> some View {
        let width = carWidth(for: screenWidth)
        let height = width / carAspect
        // Digits extend into the car; layout height accounts for overlap only once.
        let stackHeight = percentHeight + height - percentCarOverlap
        return VStack(spacing: 0) {
            Color.clear
                .frame(height: headerBlockHeight + 4)

            ZStack(alignment: .topLeading) {
                SocHeroPercent(value: socValue)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 28)
                    .offset(
                        x: -6,
                        y: 14 + percentHeight * 0.20 - scrollOffset * percentParallax
                    )
                    .opacity(Double(1 - collapseProgress * 0.35))
                    .zIndex(0)

                ZStack {
                    Group {
                        if UIImage(named: "EVHero") != nil {
                            Image("EVHero")
                                .resizable()
                                .renderingMode(.original)
                                .interpolation(.high)
                                .aspectRatio(carAspect, contentMode: .fit)
                        } else {
                            Image(systemName: "car.side.fill")
                                .font(.system(size: 72))
                                .foregroundStyle(MyNiroTheme.secondaryText)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }

                    if store.isBusy {
                        SyncStatusPill(message: store.busyMessage ?? String(localized: "Working…"))
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.86), value: store.isBusy)
                .frame(width: width, height: height)
                .frame(maxWidth: .infinity)
                .offset(y: CGFloat(percentHeight - percentCarOverlap) - scrollOffset * carParallax)
                .zIndex(1)
            }
            .frame(height: stackHeight, alignment: .top)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    private var stickyHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4 * (1 - collapseProgress)) {
                Text(store.displayName)
                    .font(.system(size: titleExpanded, weight: .bold))
                    .lineLimit(1)
                    .scaleEffect(titleScale, anchor: .leading)

                Text(VehicleStore.formatUpdated(store.lastUpdated ?? store.snapshot?.updatedAt))
                    .font(.subheadline)
                    .foregroundStyle(MyNiroTheme.secondaryText)
                    .opacity(subtitleOpacity)
                    .frame(height: subtitleHeight, alignment: .top)
                    .clipped()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.top, headerTopPadding)
        .padding(.bottom, headerBottomPadding)
        .background {
            LinearGradient(
                colors: [
                    MyNiroTheme.background.opacity(0.92 * collapseProgress),
                    MyNiroTheme.background.opacity(0.55 * collapseProgress),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        }
    }

    private var actionTiles: some View {
        VStack(spacing: 12) {
            if store.isPluggedIn && !store.displayAsCharging {
                ChargeSlideTile(
                    title: String(localized: "Plugged in"),
                    isCharging: false,
                    isPending: store.pendingAction == .charge,
                    isDisabled: store.isCommandPending,
                    scrollDragActive: $isChargeSlideDragging
                ) {
                    await store.toggleCharge()
                }
                .transition(
                    .asymmetric(
                        insertion: .opacity
                            .combined(with: .scale(scale: 0.94, anchor: .top))
                            .combined(with: .offset(y: -8)),
                        removal: .opacity
                            .combined(with: .scale(scale: 0.94, anchor: .top))
                            .combined(with: .offset(y: -8))
                    )
                )
            }

            HStack(spacing: 12) {
                ActionTile(
                    icon: store.isLocked ? "lock.fill" : "lock.open.fill",
                    title: store.isLocked
                        ? String(localized: "Locked")
                        : String(localized: "Unlocked"),
                    subtitle: store.isLocked
                        ? String(localized: "Hold to unlock")
                        : String(localized: "Hold to lock"),
                    isActive: store.isLocked,
                    isPending: store.pendingAction == .lock,
                    isDisabled: store.isCommandPending
                ) {
                    Task { await store.toggleLock() }
                }

                ActionTile(
                    icon: "snowflake",
                    title: store.climateOn
                        ? String(localized: "Climate on")
                        : String(localized: "Climate off"),
                    subtitle: store.climateOn
                        ? String(localized: "Hold to stop")
                        : String(
                            format: String(localized: "Hold · %@"),
                            String(format: "%g°", store.climateDefaults.temperatureC)
                        ),
                    isActive: store.climateOn,
                    isPending: store.pendingAction == .climate,
                    isDisabled: store.isCommandPending,
                    onAccessory: { showClimate = true }
                ) {
                    Task { await store.toggleClimate() }
                }
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: store.isPluggedIn)
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: store.displayAsCharging)
        .animation(.easeInOut(duration: 0.2), value: store.pendingAction)
    }
}

/// Large condensed SOC matching the silhouette mockup (tall digits, raised %).
private struct SocHeroPercent: View {
    let value: Int

    var body: some View {
        HStack(alignment: .top, spacing: 1) {
            Text("\(value)")
                .font(.system(size: 92, weight: .medium))
                .fontWidth(.condensed)
                .tracking(-2)

            Text("%")
                .font(.system(size: 36, weight: .medium))
                .fontWidth(.condensed)
                .padding(.top, 14)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(String(format: String(localized: "Battery %lld percent"), value))
    }
}

private struct ClearGlassCard: ViewModifier {
    var cornerRadius: CGFloat = 22
    var tint: Color? = nil

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
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

private extension View {
    func clearGlassCard(cornerRadius: CGFloat = 22, tint: Color? = nil) -> some View {
        modifier(ClearGlassCard(cornerRadius: cornerRadius, tint: tint))
    }
}

/// SOC track: filled charge, gray remainder to limit, limit slot, and gray tail.
private struct BatterySOCBar: View {
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
                    .offset(y: -(size + 6))
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

struct BatteryCard: View {
    @Bindable var store: VehicleStore
    @Binding var scrollDragActive: Bool
    var onTapLimit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: onTapLimit) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Battery")
                            .font(.headline)
                        Spacer()
                        if store.displayAsCharging {
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
                        Text("\(Int(store.socPercent.rounded()))%")
                            .font(.system(size: 40, weight: .bold))
                        Spacer()
                        Text(VehicleStore.formatKm(store.rangeKm))
                            .font(.system(size: 40, weight: .bold))
                    }

                    BatterySOCBar(
                        socPercent: store.socPercent,
                        targetSocAC: store.targetSocAC,
                        isCharging: store.displayAsCharging
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
            .buttonStyle(.plain)

            if store.displayAsCharging {
                ChargeSlideTile(
                    title: String(localized: "Charging"),
                    isCharging: true,
                    isPending: store.pendingAction == .charge,
                    isDisabled: store.isCommandPending,
                    embedded: true,
                    scrollDragActive: $scrollDragActive
                ) {
                    await store.toggleCharge()
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(18)
        .clearGlassCard()
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: store.displayAsCharging)
    }

    private var batteryEtaLabel: String {
        if let charge = store.chargeTimeText {
            if store.displayAsCharging {
                return String(format: String(localized: "Full in %@"), charge)
            }
            return String(
                format: String(localized: "Takes %1$@ to %2$lld%%"),
                charge,
                store.targetSocAC
            )
        }
        return String(format: String(localized: "Limit %lld%% AC"), store.targetSocAC)
    }

    private var chargePillText: String {
        if store.chargeSpeedKW > 0 {
            return String(format: String(localized: "Charging · %.1f kW"), store.chargeSpeedKW)
        }
        return String(localized: "Charging")
    }
}

struct ChargeSlideTile: View {
    let title: String
    let isCharging: Bool
    var isPending: Bool = false
    var isDisabled: Bool = false
    var embedded: Bool = false
    var scrollDragActive: Binding<Bool>? = nil
    let action: () async -> Bool

    @State private var dragOffset: CGFloat = 0
    @State private var didFire = false
    @State private var lastHapticStep = -1
    @GestureState private var isDragging = false
    @State private var lightHaptic = UIImpactFeedbackGenerator(style: .soft)
    @State private var mediumHaptic = UIImpactFeedbackGenerator(style: .medium)
    @State private var heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
    @State private var successHaptic = UINotificationFeedbackGenerator()

    private let trackHeight: CGFloat = 52
    private let thumbSize: CGFloat = 44
    private let inset: CGFloat = 4
    private let completeThreshold: CGFloat = 0.88
    private let hapticSteps = 8

    private var prompt: String {
        if isPending {
            return isCharging
                ? String(localized: "Stopping…")
                : String(localized: "Starting…")
        }
        return isCharging
            ? String(localized: "Slide to stop")
            : String(localized: "Slide to start charging")
    }

    private var interactionLocked: Bool { isDisabled || isPending || didFire }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 8) {
            if !embedded && (isCharging || isPending) {
                HStack(spacing: 8) {
                    if isPending {
                        ProgressView()
                            .controlSize(.small)
                            .tint(isCharging ? .black : MyNiroTheme.green)
                    } else {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.7))
                    }
                    Text(isPending
                        ? (isCharging
                            ? String(localized: "Stopping charge…")
                            : String(localized: "Starting charge…"))
                        : title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isCharging ? .black : .white)
                    Spacer(minLength: 0)
                }
            }

            GeometryReader { geo in
                let travel = max(geo.size.width - thumbSize - inset * 2, 1)
                let progress = isPending ? 1 : min(max(dragOffset / travel, 0), 1)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(usesOnTintStyle ? 0.22 : 0.08))

                    Capsule()
                        .fill(fillColor.opacity(isPending ? 0.7 : (0.35 + 0.45 * progress)))
                        .frame(width: thumbSize + inset * 2 + progress * travel)

                    if isPending {
                        ProgressView()
                            .controlSize(.regular)
                            .tint(usesOnTintStyle ? .black : .white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(prompt)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(
                                (usesOnTintStyle ? Color.black : Color.white)
                                    .opacity(0.55 * (1 - progress * 1.1))
                            )
                            .frame(maxWidth: .infinity)
                            .allowsHitTesting(false)

                        Image(systemName: isCharging ? "stop.fill" : "bolt.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(usesOnTintStyle ? .white : .black)
                            .frame(width: thumbSize, height: thumbSize)
                            .background(Circle().fill(thumbColor))
                            .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                            .offset(x: inset + dragOffset)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Capsule())
                .highPriorityGesture(slideGesture(travel: travel))
            }
            .frame(height: trackHeight)
            .onChange(of: isDragging) { _, dragging in
                scrollDragActive?.wrappedValue = dragging
            }
            .onAppear {
                lightHaptic.prepare()
                mediumHaptic.prepare()
                heavyHaptic.prepare()
                successHaptic.prepare()
            }
        }

        Group {
            if embedded {
                content
            } else {
                content
                    .padding(.horizontal, 14)
                    .padding(.vertical, (isCharging || isPending) ? 12 : 10)
                    .clearGlassCard(cornerRadius: 18, tint: isCharging ? MyNiroTheme.green : nil)
            }
        }
        .opacity(isDisabled && !isPending ? 0.55 : 1)
        .allowsHitTesting(!interactionLocked)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isCharging ? title : prompt)
        .accessibilityHint(isPending
            ? String(localized: "Updating vehicle status")
            : prompt)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard !interactionLocked else { return }
            didFire = true
            Task { await performAction() }
        }
        .onChange(of: isCharging) { _, _ in
            resetThumb(animated: false)
        }
        .onChange(of: isPending) { _, pending in
            if !pending {
                didFire = false
                resetThumb(animated: true)
            }
        }
    }

    /// Standalone stop tile sits on a green-tinted card; embedded uses dark battery glass.
    private var usesOnTintStyle: Bool { isCharging && !embedded }

    private var fillColor: Color {
        usesOnTintStyle ? Color.white : MyNiroTheme.green
    }

    private var thumbColor: Color {
        usesOnTintStyle ? Color.black.opacity(0.85) : MyNiroTheme.green
    }

    private func slideGesture(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                guard !interactionLocked else { return }
                let x = min(max(value.translation.width, 0), travel)
                dragOffset = x
                hapticForProgress(x / travel)
            }
            .onEnded { value in
                guard !interactionLocked else { return }
                let progress = min(max(value.translation.width / travel, 0), 1)
                if progress >= completeThreshold {
                    complete(travel: travel)
                } else {
                    resetThumb(animated: true)
                }
            }
    }

    private func complete(travel: CGFloat) {
        didFire = true
        lastHapticStep = -1
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            dragOffset = travel
        }
        successHaptic.notificationOccurred(.success)
        Task { await performAction() }
    }

    private func performAction() async {
        let ok = await action()
        guard !ok, !isPending else { return }
        didFire = false
        resetThumb(animated: true)
    }

    private func resetThumb(animated: Bool) {
        lastHapticStep = -1
        let reset = {
            dragOffset = 0
        }
        if animated {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82), reset)
        } else {
            reset()
        }
    }

    private func hapticForProgress(_ progress: CGFloat) {
        let step = min(Int(progress * CGFloat(hapticSteps)), hapticSteps)
        guard step != lastHapticStep, step > 0 else { return }
        lastHapticStep = step
        let intensity = 0.3 + 0.7 * progress
        if progress < 0.45 {
            lightHaptic.impactOccurred(intensity: intensity)
        } else if progress < 0.75 {
            mediumHaptic.impactOccurred(intensity: intensity)
        } else {
            heavyHaptic.impactOccurred(intensity: intensity)
        }
    }
}

struct ActionTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let isActive: Bool
    var isPending: Bool = false
    var isDisabled: Bool = false
    var holdDuration: TimeInterval = 1.0
    var onAccessory: (() -> Void)? = nil
    let action: () -> Void

    @State private var progress: CGFloat = 0
    @State private var isHolding = false
    @State private var didFire = false
    @State private var popScale: CGFloat = 1
    @State private var holdTask: Task<Void, Never>?
    @State private var lastHapticStep: Int = -1

    private let hapticSteps = 12

    private var interactionLocked: Bool { isDisabled || isPending || didFire }

    private var displayedSubtitle: String {
        isPending ? String(localized: "Updating…") : subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(isActive ? 0.2 : 0.12), lineWidth: 2.5)
                    .frame(width: 44, height: 44)

                if isPending {
                    Circle()
                        .stroke(
                            (isActive ? Color.black : MyNiroTheme.green).opacity(0.25),
                            lineWidth: 2.5
                        )
                        .frame(width: 44, height: 44)

                    ProgressView()
                        .controlSize(.regular)
                        .tint(isActive ? .black : MyNiroTheme.green)
                } else {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            isActive ? Color.black.opacity(0.55) : MyNiroTheme.green,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .frame(width: 44, height: 44)
                        .rotationEffect(.degrees(-90))

                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(
                            Circle().fill(isActive ? Color.black.opacity(0.15) : Color.white.opacity(0.1))
                        )
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(displayedSubtitle)
                    .font(.caption)
                    .opacity(0.75)
            }
        }
        .foregroundStyle(isActive ? .black : .white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .clearGlassCard(tint: isActive ? MyNiroTheme.green : nil)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(holdFill)
                .allowsHitTesting(false)
        }
        .scaleEffect(popScale * (isHolding ? 0.97 : 1))
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.82), value: isHolding)
        .overlay(alignment: .topTrailing) {
            if let onAccessory {
                Button {
                    cancelHold(resetProgress: true)
                    onAccessory()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isActive ? Color.black.opacity(0.55) : MyNiroTheme.secondaryText)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(10)
                .disabled(isDisabled)
                .opacity(isDisabled ? 0.45 : 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onLongPressGesture(
            minimumDuration: holdDuration,
            maximumDistance: 48,
            pressing: { pressing in
                guard !interactionLocked else { return }
                if pressing {
                    beginHold()
                } else if !didFire {
                    cancelHold(resetProgress: true)
                }
            },
            perform: {
                guard !interactionLocked else { return }
                fire()
            }
        )
        .opacity(isDisabled && !isPending ? 0.55 : 1)
        .allowsHitTesting(!interactionLocked || onAccessory != nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(isPending
            ? String(localized: "Updating vehicle status")
            : subtitle)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard !interactionLocked else { return }
            action()
        }
        .onChange(of: isPending) { _, pending in
            if pending {
                holdTask?.cancel()
                isHolding = false
                withAnimation(.easeOut(duration: 0.2)) {
                    progress = 0
                    popScale = 1
                }
            } else {
                didFire = false
            }
        }
    }

    private var holdFill: Color {
        guard progress > 0, !isPending else { return .clear }
        if isActive {
            return Color.black.opacity(0.12 * progress)
        }
        return MyNiroTheme.green.opacity(0.22 * progress)
    }

    private func beginHold() {
        holdTask?.cancel()
        isHolding = true
        didFire = false
        lastHapticStep = -1
        progress = 0
        lightImpact(intensity: 0.35)

        withAnimation(.linear(duration: holdDuration)) {
            progress = 1
        }

        holdTask = Task { @MainActor in
            let tickNanos = UInt64((holdDuration / Double(hapticSteps)) * 1_000_000_000)
            for step in 0..<hapticSteps {
                try? await Task.sleep(nanoseconds: tickNanos)
                guard !Task.isCancelled else { return }
                let t = CGFloat(step + 1) / CGFloat(hapticSteps)
                escalateHaptic(progress: t, step: step)
            }
        }
    }

    private func cancelHold(resetProgress: Bool) {
        holdTask?.cancel()
        holdTask = nil
        isHolding = false
        lastHapticStep = -1
        if resetProgress {
            withAnimation(.easeOut(duration: 0.22)) {
                progress = 0
            }
        }
    }

    private func fire() {
        holdTask?.cancel()
        holdTask = nil
        didFire = true
        isHolding = false

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
            popScale = 1.06
            progress = 1
        }
        action()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                popScale = 1
                if !isPending {
                    progress = 0
                }
            }
        }
    }

    private func escalateHaptic(progress: CGFloat, step: Int) {
        guard step != lastHapticStep else { return }
        lastHapticStep = step

        let intensity = 0.28 + 0.72 * progress
        if progress < 0.34 {
            lightImpact(intensity: intensity)
        } else if progress < 0.67 {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: intensity)
        } else if progress < 1 {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: intensity)
        }
    }

    private func lightImpact(intensity: CGFloat) {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: intensity)
    }
}
