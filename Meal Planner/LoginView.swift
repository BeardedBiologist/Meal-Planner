import SwiftUI
import AuthenticationServices

struct LoginView: View {
    var onLogin: () -> Void
    var onSignup: () -> Void

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
                    SignInWithAppleButton(.signIn, onRequest: { request in
                        // Configure Apple request if needed
                    }, onCompletion: { result in
                        switch result {
                        case .success(_):
                            onLogin()
                        case .failure(let error):
                            // Optionally show an error
                            print(error.localizedDescription)
                        }
                    })
                    .frame(height: 48)
                    .cornerRadius(10)
                    .padding(.top, 16)

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
