import SwiftUI

private enum AuthMode {
    case signIn, register

    var buttonLabel: String   { self == .signIn ? "Sign In" : "Create Account" }
    var switchPrompt: String  { self == .signIn ? "Don't have an account?" : "Already have an account?" }
    var switchLabel: String   { self == .signIn ? "Create one" : "Sign in" }
    var toggled: AuthMode     { self == .signIn ? .register : .signIn }
}

struct LoginView: View {
    @Environment(AuthService.self) private var auth

    @State private var mode: AuthMode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 64)

                brandHeader

                Spacer().frame(height: 40)

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

                Spacer().frame(height: 20)

                actionButton
                    .padding(.horizontal, 24)

                Spacer().frame(height: 24)

                switchModeButton

                Spacer().frame(height: 48)
            }
        }
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .animation(.easeInOut(duration: 0.22), value: mode)
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
            Text(mode == .signIn ? "Welcome back." : "Create your account.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
    }

    // MARK: - Form Card

    private var formCard: some View {
        VStack(spacing: 0) {
            if mode == .register {
                FormRow(icon: "person") {
                    TextField("Full Name", text: $name)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                }
                .transition(.move(edge: .top).combined(with: .opacity))

                Divider().padding(.leading, 52)
            }

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
                            .textContentType(mode == .register ? .newPassword : .password)
                    } else {
                        SecureField("Password", text: $password)
                            .textContentType(mode == .register ? .newPassword : .password)
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

            if mode == .register {
                Divider().padding(.leading, 52)

                FormRow(icon: "lock.shield") {
                    SecureField("Confirm Password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipped()
    }

    // MARK: - Action Button

    private var actionButton: some View {
        Button {
            Task { await submit() }
        } label: {
            ZStack {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(mode.buttonLabel)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                isSubmitDisabled ? Color.secondary.opacity(0.3) : Color.red,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .disabled(isSubmitDisabled || isLoading)
    }

    // MARK: - Switch Mode

    private var switchModeButton: some View {
        HStack(spacing: 4) {
            Text(mode.switchPrompt)
                .foregroundStyle(.secondary)
            Button(mode.switchLabel) {
                errorMessage = nil
                name = ""
                password = ""
                confirmPassword = ""
                mode = mode.toggled
            }
            .foregroundStyle(.red)
        }
        .font(.subheadline)
    }

    // MARK: - Validation

    private var isSubmitDisabled: Bool {
        if isLoading { return true }
        if mode == .signIn {
            return email.isEmpty || password.isEmpty
        } else {
            return name.trimmingCharacters(in: .whitespaces).isEmpty
                || email.isEmpty
                || password.count < 8
                || confirmPassword != password
        }
    }

    // MARK: - Submit

    private func submit() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        let trimmedEmail = email.lowercased().trimmingCharacters(in: .whitespaces)
        let trimmedName  = name.trimmingCharacters(in: .whitespaces)

        do {
            if mode == .signIn {
                try await auth.signIn(email: trimmedEmail, password: password)
            } else {
                guard password == confirmPassword else {
                    errorMessage = "Passwords don't match."
                    return
                }
                try await auth.signUp(name: trimmedName, email: trimmedEmail, password: password)
            }
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
