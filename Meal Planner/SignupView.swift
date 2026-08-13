import SwiftUI
import AuthenticationServices

struct SignupView: View {
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
                SignInWithAppleButton(.signUp, onRequest: { request in
                    // Configure Apple request if needed
                }, onCompletion: { result in
                    switch result {
                    case .success(_):
                        onSignup()
                    case .failure(let error):
                        // Optionally show an error
                        print(error.localizedDescription)
                    }
                })
                .frame(height: 48)
                .cornerRadius(10)
                .padding(.top, 16)
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
