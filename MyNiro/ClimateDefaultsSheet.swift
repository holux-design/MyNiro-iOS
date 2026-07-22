import SwiftUI

struct ClimateDefaultsSheet: View {
    @Bindable var store: VehicleStore
    @Environment(\.dismiss) private var dismiss
    @State private var temperatureC: Double

    init(store: VehicleStore) {
        self.store = store
        _temperatureC = State(initialValue: min(27, max(17, store.climateDefaults.temperatureC)))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Text("Climate temperature")
                    .font(.title2.bold())

                HStack {
                    roundButton(system: "minus") {
                        temperatureC = max(17, (temperatureC * 2).rounded() / 2 - 0.5)
                    }
                    Spacer()
                    VStack(spacing: 4) {
                        Text(String(format: "%g°", temperatureC))
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundStyle(MyNiroTheme.green)
                        Text("Target · 17–27°C")
                            .font(.caption)
                            .foregroundStyle(MyNiroTheme.secondaryText)
                    }
                    Spacer()
                    roundButton(system: "plus", filled: true) {
                        temperatureC = min(27, (temperatureC * 2).rounded() / 2 + 0.5)
                    }
                }

                Text("Used when you start climate from the Car tab.")
                    .font(.footnote)
                    .foregroundStyle(MyNiroTheme.secondaryText)
                    .multilineTextAlignment(.center)

                Button {
                    var defaults = store.climateDefaults
                    defaults.temperatureC = temperatureC
                    store.saveClimateDefaults(defaults)
                    dismiss()
                } label: {
                    Text("Save")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(MyNiroTheme.green, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.black)
                }

                Spacer()
            }
            .padding(24)
            .background(MyNiroTheme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func roundButton(system: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.title3.weight(.semibold))
                .frame(width: 48, height: 48)
                .background(Circle().fill(filled ? MyNiroTheme.green : MyNiroTheme.cardElevated))
                .foregroundStyle(filled ? .black : .white)
        }
        .buttonStyle(.plain)
    }
}

struct ChargeLimitSheet: View {
    @Bindable var store: VehicleStore
    @State private var limit: Double

    init(store: VehicleStore) {
        self.store = store
        _limit = State(initialValue: Double(store.targetSocAC))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Text("AC charge limit")
                    .font(.title2.bold())
                Text("\(Int(limit))%")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(MyNiroTheme.green)

                Slider(value: $limit, in: 50...100, step: 10)
                    .tint(MyNiroTheme.green)

                Text("Sets the target state of charge for AC charging.")
                    .font(.footnote)
                    .foregroundStyle(MyNiroTheme.secondaryText)
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .padding(24)
            .background(MyNiroTheme.background)
        }
        .preferredColorScheme(.dark)
        .onDisappear {
            let value = Int(limit)
            guard value != store.targetSocAC else { return }
            Task { await store.setACChargeLimit(value) }
        }
    }
}
