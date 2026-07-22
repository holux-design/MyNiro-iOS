import SwiftUI

struct RootView: View {
    @Bindable var store: VehicleStore
    @State private var showSettings = false

    var body: some View {
        ZStack {
            MyNiroTheme.background.ignoresSafeArea()

            if store.isLoggedIn {
                CarTabView(store: store) {
                    showSettings = true
                }
                .sheet(isPresented: $showSettings) {
                    SettingsTabView(store: store)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
            } else {
                LoginView(store: store)
            }

            if store.isBusy && (!store.isLoggedIn || showSettings) {
                SyncStatusBanner(message: store.busyMessage ?? String(localized: "Working…"))
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .animation(.spring, value: store.isBusy)
            }

            if let toast = store.toastMessage {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 40)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring, value: store.toastMessage)
            }
        }
        .preferredColorScheme(.dark)
        .alert("Error", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

struct SyncStatusPill: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(MyNiroTheme.green)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .modifier(SyncBannerChrome())
        .allowsHitTesting(false)
    }
}

struct SyncStatusBanner: View {
    let message: String

    var body: some View {
        SyncStatusPill(message: message)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
    }
}

private struct SyncBannerChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.clear, in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        }
    }
}
