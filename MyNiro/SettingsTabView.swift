import AppIntents
import SwiftUI

struct SettingsTabView: View {
    @Bindable var store: VehicleStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("ACCOUNT") {
                        VStack(alignment: .leading, spacing: 12) {
                            row("Email", store.email)
                            row("Region", "Europe")
                            row("Brand", "Kia")
                        }
                        .padding(16)
                        .background(MyNiroTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    section("SIRI") {
                        VStack(alignment: .leading, spacing: 8) {
                            ShortcutsLink()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(String(localized: "Siri shortcuts hint"))
                                .font(.footnote)
                                .foregroundStyle(MyNiroTheme.tertiaryText)
                        }
                        .padding(16)
                        .background(MyNiroTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    section("DATA") {
                        Button {
                            Task { await store.refresh(force: true) }
                        } label: {
                            settingsButton(title: "Refresh vehicle now", system: "arrow.clockwise")
                        }
                    }

                    Button(role: .destructive) {
                        store.logout()
                        dismiss()
                    } label: {
                        Text("Sign Out")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(MyNiroTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(.red)
                    }

                    Text(String(localized: "Unofficial disclaimer"))
                        .font(.footnote)
                        .foregroundStyle(MyNiroTheme.tertiaryText)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(MyNiroTheme.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(MyNiroTheme.green)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedStringKey(title))
                .font(.caption.weight(.semibold))
                .foregroundStyle(MyNiroTheme.secondaryText)
            content()
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(LocalizedStringKey(title))
                .foregroundStyle(MyNiroTheme.secondaryText)
            Spacer()
            Text(value == "Europe" || value == "Kia" ? String(localized: String.LocalizationValue(value)) : value)
                .fontWeight(.medium)
        }
    }

    private func settingsButton(title: String, system: String) -> some View {
        HStack {
            Image(systemName: system)
            Text(LocalizedStringKey(title))
                .fontWeight(.semibold)
            Spacer()
        }
        .padding(16)
        .background(MyNiroTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .foregroundStyle(.white)
    }
}
