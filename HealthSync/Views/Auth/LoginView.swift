import SwiftUI

struct LoginView: View {
    @Environment(AuthService.self) private var auth

    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 64)

                brandHeader

                Spacer().frame(height: 48)

                formCard
                    .padding(.horizontal, 24)

                if let error = errorMessage {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                }

                Spacer().frame(height: 32)

                actionButton
                    .padding(.horizontal, 24)

                Spacer().frame(height: 48)
            }
        }
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Brand Header

    private var brandHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.red, Color.red.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                Image(systemName: "heart.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white)
            }
            Text("HealthSync")
                .font(.system(size: 28, weight: .bold))
            Text("Your personal health data, synced.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Form

    private var formCard: some View {
        VStack(spacing: 0) {
            FormRow(icon: "envelope") {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            Divider().padding(.leading, 52)
            FormRow(icon: "lock") {
                Group {
                    if showPassword {
                        TextField("Password", text: $password)
                            .textContentType(.password)
                    } else {
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                    }
                }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Action Button

    private var actionButton: some View {
        Button {
            Task { await submit() }
        } label: {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Sign In")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                isSubmitDisabled
                    ? Color.secondary.opacity(0.3)
                    : Color.red,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .disabled(isSubmitDisabled || isLoading)
    }

    private var isSubmitDisabled: Bool {
        isLoading || email.isEmpty || password.isEmpty
    }

    // MARK: - Submit

    private func submit() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            try await auth.signIn(email: email.lowercased().trimmingCharacters(in: .whitespaces), password: password)
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Form Row

private struct FormRow<Content: View>: View {
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 28)
                .padding(.leading, 16)
            content()
                .padding(.trailing, 16)
        }
        .frame(height: 52)
    }
}

#Preview {
    LoginView()
        .environment(AuthService.shared)
}
