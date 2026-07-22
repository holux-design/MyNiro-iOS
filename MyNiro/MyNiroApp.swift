import SwiftUI

@main
struct MyNiroApp: App {
    @State private var store = VehicleStore.shared

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
        }
    }
}
