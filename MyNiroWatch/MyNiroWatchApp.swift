import SwiftUI

@main
struct MyNiroWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = VehicleStore.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView(store: store)
                .onAppear {
                    PhoneWatchSync.shared.activate()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        PhoneWatchSync.shared.activate()
                    }
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "myniro" else { return }
        switch url.host {
        case "unlock":
            Task { await store.unlock() }
        default:
            break
        }
    }
}

struct WatchRootView: View {
    @Bindable var store: VehicleStore

    var body: some View {
        NavigationStack {
            if store.isLoggedIn || store.snapshot != nil {
                ScrollView {
                    VStack(spacing: 12) {
                        VStack(spacing: 4) {
                            Text("\(Int(store.socPercent.rounded()))%")
                                .font(.largeTitle.bold())
                            Text(VehicleStore.formatKm(store.rangeKm))
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(MyNiroTheme.green)
                        }
                        .padding(.vertical, 8)

                        if store.isCommandPending, store.pendingAction == .lock {
                            ProgressView(String(localized: "Unlocking…"))
                                .tint(MyNiroTheme.green)
                        }

                        Button {
                            Task { await store.unlock() }
                        } label: {
                            Label(String(localized: "Unlock"), systemImage: "lock.open.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .tint(MyNiroTheme.green)
                        .disabled(store.isBusy)

                        Button {
                            Task { await store.toggleClimate() }
                        } label: {
                            Label(
                                store.climateOn
                                    ? String(localized: "Stop Climate")
                                    : String(localized: "Start Climate"),
                                systemImage: "snowflake"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(store.isBusy)

                        Button {
                            Task { await store.refresh(force: true) }
                        } label: {
                            Label(String(localized: "Refresh"), systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(store.isBusy)

                        if let toast = store.toastMessage {
                            Text(toast)
                                .font(.caption)
                                .foregroundStyle(MyNiroTheme.green)
                        } else if let error = store.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .navigationTitle(store.displayName)
                .containerBackground(MyNiroTheme.background.gradient, for: .navigation)
            } else {
                ContentUnavailableView(
                    String(localized: "Open iPhone"),
                    systemImage: "iphone",
                    description: Text(String(localized: "Sign in on your iPhone to control the car from Apple Watch."))
                )
            }
        }
        .preferredColorScheme(.dark)
    }
}
