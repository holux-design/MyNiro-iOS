import AppIntents
import SwiftUI
import WidgetKit

@main
struct MyNiroWidgetBundle: WidgetBundle {
    var body: some Widget {
        BatteryStatusWidget()
        UnlockControlWidget()
    }
}

struct BatteryEntry: TimelineEntry {
    let date: Date
    let snapshot: CachedVehicleSnapshot?
    let feedback: WidgetActionFeedback?

    init(date: Date, snapshot: CachedVehicleSnapshot?, feedback: WidgetActionFeedback? = nil) {
        self.date = date
        self.snapshot = snapshot
        self.feedback = feedback
    }
}

struct BatteryProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry {
        BatteryEntry(date: .now, snapshot: sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        let now = Date.now
        completion(
            BatteryEntry(
                date: now,
                snapshot: CachedVehicleSnapshot.load() ?? sample,
                feedback: WidgetActionFeedback.active(at: now)
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        let now = Date.now
        let snap = CachedVehicleSnapshot.load()
        let feedback = WidgetActionFeedback.active(at: now)
        var entries = [BatteryEntry(date: now, snapshot: snap, feedback: feedback)]

        if let feedback, feedback.expiresAt > now {
            entries.append(BatteryEntry(date: feedback.expiresAt, snapshot: snap, feedback: nil))
            let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: feedback.expiresAt)
                ?? feedback.expiresAt.addingTimeInterval(900)
            completion(Timeline(entries: entries, policy: .after(refresh)))
        } else {
            let next = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
            completion(Timeline(entries: entries, policy: .after(next)))
        }
    }

    private var sample: CachedVehicleSnapshot {
        CachedVehicleSnapshot(
            vehicleName: "My EV9",
            vin: "SAMPLE",
            socPercent: 67,
            rangeKm: 293,
            isCharging: true,
            isPluggedIn: true,
            chargeSpeedKW: 0.7,
            targetSocAC: 80,
            isLocked: true,
            climateOn: false,
            climateTempC: 22,
            updatedAt: .now,
            chargeTimeSeconds: 3600,
            latitude: nil,
            longitude: nil
        )
    }
}

struct BatteryStatusWidget: Widget {
    let kind = "BatteryStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BatteryProvider()) { entry in
            BatteryWidgetView(entry: entry)
                .containerBackground(for: .widget) { MyNiroTheme.background }
        }
        .configurationDisplayName(LocalizedStringResource("My Niro"))
        .description(LocalizedStringResource("Battery, climate, unlock, and charge"))
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

struct BatteryWidgetView: View {
    let entry: BatteryEntry

    private var snap: CachedVehicleSnapshot? { entry.snapshot }
    private var soc: Int { Int((snap?.socPercent ?? 0).rounded()) }
    private var socFraction: CGFloat {
        min(max(CGFloat(snap?.socPercent ?? 0) / 100, 0), 1)
    }
    private var isLocked: Bool { snap?.isLocked ?? true }
    private var climateOn: Bool { snap?.climateOn ?? false }
    private var isCharging: Bool { snap?.isCharging ?? false }
    private var isPluggedIn: Bool { snap?.isPluggedIn ?? false }
    private var climateTempLabel: String {
        let temp = ClimateDefaults.load().temperatureC
        return String(format: "%g°", temp)
    }

    var body: some View {
        VStack(spacing: 8) {
            actionRow
            Group {
                if isCharging {
                    chargingBatteryCard
                } else {
                    VStack(spacing: 0) {
                        hero
                        batteryBar
                            .padding(.top, 16)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(8)
    }

    private var chargingBatteryCard: some View {
        BatteryStatusCard(
            socPercent: snap?.socPercent ?? 0,
            rangeKm: snap?.rangeKm ?? 0,
            targetSocAC: Int(snap?.targetSocAC ?? 80),
            isCharging: true,
            chargeSpeedKW: snap?.chargeSpeedKW ?? 0,
            chargeTimeText: chargeTimeText,
            expandsVertically: true
        )
    }

    private var chargeTimeText: String? {
        guard let seconds = snap?.chargeTimeSeconds, seconds > 0 else { return nil }
        return VehicleStore.formatDuration(seconds: seconds)
    }

    private var hero: some View {
        let carAspect: CGFloat = 1024.0 / 399.0
        let percentSize: CGFloat = 72
        let percentHeight: CGFloat = 70
        let overlap: CGFloat = 36

        return ZStack(alignment: .top) {
            HStack(alignment: .top, spacing: 1) {
                Text("\(soc)")
                    .font(.system(size: percentSize, weight: .medium))
                    .fontWidth(.condensed)
                    .tracking(-2)

                Text("%")
                    .font(.system(size: percentSize * 0.38, weight: .medium))
                    .fontWidth(.condensed)
                    .padding(.top, percentSize * 0.15)
            }
            .foregroundStyle(.white)
            .padding(.leading, -4)
            .padding(.top, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: percentHeight, alignment: .top)
            .zIndex(0)
            .accessibilityLabel(String(format: String(localized: "Battery %lld percent"), soc))

            Image("EVHero")
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .aspectRatio(carAspect, contentMode: .fit)
                .padding(.horizontal, -18)
                .padding(.top, percentHeight - overlap)
                .frame(maxWidth: .infinity, alignment: .bottom)
                .zIndex(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var batteryBar: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(VehicleStore.formatKm(snap?.rangeKm ?? 0))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(MyNiroTheme.green)
                        .frame(width: geo.size.width * socFraction)
                }
            }
            .frame(height: 8)
        }
    }

    private var actionRow: some View {
        ZStack {
            HStack(spacing: 8) {
                WidgetActionTile(
                    intent: ToggleClimateIntent(),
                    icon: "snowflake",
                    label: climateOn
                        ? String(format: String(localized: "On · %@"), climateTempLabel)
                        : climateTempLabel,
                    isActive: climateOn
                )
                WidgetActionTile(
                    intent: ToggleLockIntent(),
                    icon: isLocked ? "lock.open.fill" : "lock.fill",
                    label: isLocked ? String(localized: "Unlock") : String(localized: "Lock"),
                    isActive: isLocked
                )
                WidgetActionTile(
                    intent: ToggleChargeIntent(),
                    icon: isCharging ? "bolt.fill" : "bolt",
                    label: isCharging
                        ? String(localized: "Stop")
                        : (isPluggedIn ? String(localized: "Start") : String(localized: "Plug in")),
                    isActive: isCharging,
                    isDisabled: !isPluggedIn && !isCharging
                )
            }
            .opacity(entry.feedback == nil ? 1 : 0)
            .allowsHitTesting(entry.feedback == nil)

            if let feedback = entry.feedback {
                widgetStatusMessage(feedback)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.35), value: entry.feedback?.message)
    }

    private func widgetStatusMessage(_ feedback: WidgetActionFeedback) -> some View {
        let icon: String = {
            switch feedback.isSuccess {
            case true: return "checkmark.circle.fill"
            case false: return "exclamationmark.circle.fill"
            case nil: return "arrow.triangle.2.circlepath"
            }
        }()
        let tint: Color = {
            switch feedback.isSuccess {
            case true: return MyNiroTheme.green
            case false: return Color.orange
            case nil: return Color.white.opacity(0.85)
            }
        }()

        return VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(tint)
            Text(feedback.message)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        }
    }
}

private struct WidgetActionTile<I: AppIntent>: View {
    let intent: I
    let icon: String
    let label: String
    var isActive: Bool = false
    var isDisabled: Bool = false

    var body: some View {
        Button(intent: intent) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(isActive ? Color.black : Color.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isActive ? MyNiroTheme.green : Color.white.opacity(0.08))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(isActive ? 0 : 0.14), lineWidth: 1)
            }
            .opacity(isDisabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .disabled(isDisabled)
    }
}

struct UnlockControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "UnlockControl") {
            ControlWidgetButton(action: UnlockVehicleIntent()) {
                Label(String(localized: "Unlock"), systemImage: "lock.open.fill")
            }
        }
        .displayName(LocalizedStringResource("Unlock Car"))
        .description(LocalizedStringResource("Unlock your Kia from Control Center"))
    }
}
