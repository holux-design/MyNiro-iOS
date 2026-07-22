import SwiftUI

@main
struct MyNiroApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = VehicleStore.shared

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .onAppear {
                    PhoneWatchSync.shared.activate()
                    store.syncSessionToWatch()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        PhoneWatchSync.shared.activate()
                        store.syncSessionToWatch()
                    }
                }
        }
    }
}
