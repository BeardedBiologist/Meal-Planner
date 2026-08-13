import Foundation
import AuthenticationServices
import Security
import Observation

@MainActor
@Observable
class AuthenticationManager {
    static let shared = AuthenticationManager()

    private static let isAuthenticatedKey = "isAuthenticated"
    private static let appleUserIdKey = "appleUserId"

    private(set) var isAuthenticated: Bool

    private init() {
        isAuthenticated = UserDefaults.standard.bool(forKey: Self.isAuthenticatedKey)
    }

    func handleAppleSignIn(result: Result<ASAuthorization, Error>, completion: @escaping (Bool) -> Void) {
        switch result {
        case .success(let auth):
            if let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                let userId = credential.user
                saveToKeychain(userId: userId)
                setAuthenticated(true)
                completion(true)
            } else {
                completion(false)
            }
        case .failure:
            completion(false)
        }
    }

#if DEBUG
    func mockSignIn() {
        saveToKeychain(userId: "mock_user_123")
        setAuthenticated(true)
    }
#endif

    func signOut() {
        setAuthenticated(false)
    }

    func isUserSignedUp() -> Bool {
        return getFromKeychain() != nil
    }

    private func setAuthenticated(_ value: Bool) {
        isAuthenticated = value
        UserDefaults.standard.set(value, forKey: Self.isAuthenticatedKey)
    }

    private func saveToKeychain(userId: String) {
        let data = Data(userId.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Self.appleUserIdKey,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func getFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Self.appleUserIdKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        if status == errSecSuccess, let data = dataTypeRef as? Data, let userId = String(data: data, encoding: .utf8) {
            return userId
        }
        return nil
    }
}
