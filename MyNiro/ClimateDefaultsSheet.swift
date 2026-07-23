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
    @State private var limit: Int

    private static let options = [50, 60, 70, 80, 90, 100]

    init(store: VehicleStore) {
        self.store = store
        _limit = State(initialValue: Self.nearestOption(to: store.targetSocAC))
    }

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            GlassOptionSelect(options: Self.options, selection: $limit) { value in
                Text("\(value)")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MyNiroTheme.background)
        .preferredColorScheme(.dark)
        .accessibilityLabel(String(localized: "AC charge limit"))
        .onDisappear {
            guard limit != store.targetSocAC else { return }
            Task { await store.setACChargeLimit(limit) }
        }
    }

    private static func nearestOption(to value: Int) -> Int {
        options.min(by: { abs($0 - value) < abs($1 - value) }) ?? 80
    }
}

private struct GlassOptionSelect<Option: Hashable, Label: View>: View {
    let options: [Option]
    @Binding var selection: Option
    @ViewBuilder var label: (Option) -> Label

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    label(option)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(MyNiroTheme.green)
                    }
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .modifier(ClearGlassCapsule())
    }
}

private struct ClearGlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(Glass.clear.interactive(), in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        }
    }
}
