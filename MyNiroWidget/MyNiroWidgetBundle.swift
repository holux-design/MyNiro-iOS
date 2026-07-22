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
}

struct BatteryProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry {
        BatteryEntry(date: .now, snapshot: sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        completion(BatteryEntry(date: .now, snapshot: CachedVehicleSnapshot.load() ?? sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        let entry = BatteryEntry(date: .now, snapshot: CachedVehicleSnapshot.load())
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
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
            chargeTimeSeconds: 3600
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
        VStack(spacing: 0) {
            actionRow
            Spacer(minLength: 8)
            hero
            batteryBar
                .padding(.top, 16)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 14)
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
                icon: isLocked ? "lock.fill" : "lock.open.fill",
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
        .frame(maxWidth: .infinity)
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
