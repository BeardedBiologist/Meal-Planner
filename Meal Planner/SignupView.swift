import SwiftUI
import AuthenticationServices

struct SignupView: View {
    private let authManager = AuthenticationManager.shared
    var onSignup: () -> Void
    var onLogin: () -> Void

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
                    Text("Create your account")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
#if DEBUG
                Button(action: {
                    authManager.mockSignIn()
                    onSignup()
                }) {
                    Text("Continue as Test User")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
#else
                SignInWithAppleButton(.signUp, onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                }, onCompletion: { result in
                    authManager.handleAppleSignIn(result: result) { success in
                        if success { onSignup() }
                    }
                })
                .frame(height: 48)
                .cornerRadius(10)
#endif

                Button(action: onLogin) {
                    Text("Already have an account? Log In")
                        .font(.footnote)
                        .foregroundColor(.accentColor)
                        .padding(.top, 4)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }
}

#Preview {
    SignupView(onSignup: {}, onLogin: {})
}
