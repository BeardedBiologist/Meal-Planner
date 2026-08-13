import SwiftUI

struct LandingView: View {
    @State private var showLogin = false
    @State private var showSignup = false

    var onLogin: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("Meal Planner")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Plan meals, track grocery expenses, and optimize your shopping!")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            VStack(spacing: 16) {
                Button(action: { showLogin = true }) {
                    Text("Log In")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }

                Button(action: { showSignup = true }) {
                    Text("Sign Up")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal)
            Spacer()
        }
        .sheet(isPresented: $showLogin) {
            LoginView(onLogin: {
                showLogin = false
                onLogin()
            }, onSignup: {
                showLogin = false
                showSignup = true
            })
        }
        .sheet(isPresented: $showSignup) {
            SignupView(onSignup: {
                showSignup = false
                onLogin()
            }, onLogin: {
                showSignup = false
                showLogin = true
            })
        }
    }
}

#Preview {
    LandingView(onLogin: {})
}
