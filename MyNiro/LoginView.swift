import SwiftUI

struct LoginView: View {
    @Bindable var store: VehicleStore
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("MyNiro")
                        .font(.largeTitle.bold())
                    Text("Sign in with your Kia Connect Europe account")
                        .foregroundStyle(MyNiroTheme.secondaryText)
                }
                .padding(.top, 48)

                field("Email", text: $email, contentType: .username)
                field("Password", text: $password, contentType: .password, secure: true)

                Button {
                    Task {
                        await store.login(
                            email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                            password: password,
                            pin: ""
                        )
                    }
                } label: {
                    Group {
                        if store.isLoading {
                            ProgressView().tint(.black)
                        } else {
                            Text("Sign In").fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(MyNiroTheme.green, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.black)
                }
                .disabled(store.isLoading || email.isEmpty || password.isEmpty)
                .opacity(email.isEmpty || password.isEmpty ? 0.5 : 1)

                Text("Same email and password as the official Kia Connect app. No PIN needed to sign in — if remote commands ask for one later, you can add it in Settings.")
                    .font(.footnote)
                    .foregroundStyle(MyNiroTheme.tertiaryText)
            }
            .padding(24)
        }
    }

    private func field(
        _ title: String,
        text: Binding<String>,
        contentType: UITextContentType,
        secure: Bool = false
    ) -> some View {
        let localizedTitle = String(localized: String.LocalizationValue(title))
        return VStack(alignment: .leading, spacing: 8) {
            Text(localizedTitle.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(MyNiroTheme.secondaryText)
            Group {
                if secure {
                    SecureField(localizedTitle, text: text)
                } else {
                    TextField(localizedTitle, text: text)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                }
            }
            .textContentType(contentType)
            .padding(16)
            .background(MyNiroTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
