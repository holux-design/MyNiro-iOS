import AppIntents
import SwiftUI
import WidgetKit

@main
struct MyNiroWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        UnlockComplication()
        StatusComplication()
    }
}

// MARK: - Unlock (circular tap target)

enum WatchDeepLink {
    static let unlock = URL(string: "myniro://unlock")!
}

struct UnlockComplication: Widget {
    let kind = "UnlockComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UnlockProvider()) { _ in
            UnlockComplicationView()
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName(LocalizedStringResource("Unlock"))
        .description(LocalizedStringResource("Unlock your Kia"))
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

struct UnlockProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry { SimpleEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        completion(Timeline(entries: [SimpleEntry(date: .now)], policy: .never))
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
}

struct UnlockComplicationView: View {
    var body: some View {
        // Watch-face complications often ignore Button(intent:) and only open the app.
        // widgetURL → app handles unlock immediately on launch.
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "lock.open.fill")
                .font(.system(size: 18, weight: .semibold))
                .widgetAccentable()
        }
        .widgetURL(WatchDeepLink.unlock)
    }
}

// MARK: - Battery status

struct WatchEntry: TimelineEntry {
    let date: Date
    let snapshot: CachedVehicleSnapshot?
}

struct WatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchEntry {
        WatchEntry(date: .now, snapshot: CachedVehicleSnapshot(
            vehicleName: "EV9", vin: "", socPercent: 67, rangeKm: 293,
            isCharging: false, isPluggedIn: false, chargeSpeedKW: nil,
            targetSocAC: 80, isLocked: true, climateOn: false,
            climateTempC: 22, updatedAt: .now, chargeTimeSeconds: nil,
            latitude: nil, longitude: nil
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        completion(WatchEntry(date: .now, snapshot: CachedVehicleSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        let entry = WatchEntry(date: .now, snapshot: CachedVehicleSnapshot.load())
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct StatusComplication: Widget {
    let kind = "StatusComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchProvider()) { entry in
            StatusComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName(LocalizedStringResource("Battery"))
        .description(LocalizedStringResource("SOC and range"))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct StatusComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchEntry

    var body: some View {
        let soc = Int((entry.snapshot?.socPercent ?? 0).rounded())
        let km = Int((entry.snapshot?.rangeKm ?? 0).rounded())
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(soc), in: 0...100) {
                Text("SOC")
            } currentValueLabel: {
                Text("\(soc)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.snapshot?.vehicleName ?? "MyNiro")
                    .font(.headline)
                Text("\(soc)% · \(km) km")
            }
        case .accessoryInline:
            Text("\(soc)% · \(km) km")
        default:
            Text("\(soc)%")
                .font(.headline)
        }
    }
}
