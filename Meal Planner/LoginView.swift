import SwiftUI
import AuthenticationServices

struct LoginView: View {
    var onLogin: () -> Void
    var onSignup: () -> Void

    private let authManager = AuthenticationManager.shared

    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [Color.accentColor.opacity(0.12), Color(.systemBackground)]), startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 30) {
                Spacer()
                VStack(spacing: 8) {
                    Text("Meal Planner")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Sign in to your account")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                VStack(spacing: 16) {
#if DEBUG
                    Button(action: {
                        authManager.mockSignIn()
                        onLogin()
                    }) {
                        Text("Continue as Test User")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
#else
                    SignInWithAppleButton(.signIn, onRequest: { request in
                        request.requestedScopes = [.fullName, .email]
                    }, onCompletion: { result in
                        authManager.handleAppleSignIn(result: result) { success in
                            if success { onLogin() }
                        }
                    })
                    .frame(height: 48)
                    .cornerRadius(10)
#endif

                    Button(action: onSignup) {
                        Text("Don't have an account? Sign Up")
                            .font(.footnote)
                            .foregroundColor(.accentColor)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal)
                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }
}

#Preview {
    LoginView(onLogin: {}, onSignup: {})
}
