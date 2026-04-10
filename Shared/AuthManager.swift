//
//  AuthManager.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import AuthenticationServices
import CryptoKit
import Foundation
import os
#if canImport(AppKit)
import AppKit
#endif

private let logger = Logger(subsystem: "org.davidjensenius.GT3Companion", category: "AuthManager")

// Provides a presentation anchor for ASWebAuthenticationSession cross-platform.
private class AuthAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        return NSApp.keyWindow ?? NSWindow()
        #elseif os(iOS) || os(visionOS)
        if let app = (NSClassFromString("UIApplication") as? NSObject.Type)?
            .value(forKeyPath: "sharedApplication") as? NSObject,
           let scenes = app.value(forKey: "connectedScenes") as? Set<NSObject> {
            for scene in scenes {
                if String(describing: type(of: scene)).contains("UIWindowScene"),
                   let windows = scene.value(forKey: "windows") as? [NSObject] {
                    for window in windows {
                        if let isKey = window.value(forKey: "isKeyWindow") as? Bool, isKey {
                            return window as! ASPresentationAnchor // swiftlint:disable:this force_cast
                        }
                    }
                    if let first = windows.first {
                        return first as! ASPresentationAnchor // swiftlint:disable:this force_cast
                    }
                }
            }
        }
        if #unavailable(iOS 26, visionOS 26) {
            return ASPresentationAnchor(frame: .zero)
        }
        // Safe fallback: return a detached UIWindow rather than crashing.
        // ASWebAuthenticationSession may still present on it; if not, the
        // auth call will throw and AuthManager handles it gracefully.
        logger.warning("No key window found for ASWebAuthenticationSession — using detached UIWindow")
        return UIWindow()
        #else
        return ASPresentationAnchor(frame: .zero)
        #endif
    }
}

// MARK: - Supporting types

enum AuthError: Error, LocalizedError {
    case noCode
    case tokenExchangeFailed(String)
    case cancelled
    case unknown
    /// Server explicitly rejected the refresh token (4xx). The session is dead and the user must re-authenticate.
    case refreshTokenInvalid(String)
    /// The refresh request failed for a transient reason (network down, DNS, 5xx). Session is kept alive.
    case transientRefreshFailure(Error)

    var errorDescription: String? {
        switch self {
        case .noCode: return "No authorization code received"
        case .tokenExchangeFailed(let msg): return "Token exchange failed: \(msg)"
        case .cancelled: return "Sign in was cancelled"
        case .unknown: return "An unknown error occurred"
        case .refreshTokenInvalid(let msg): return "Session expired: \(msg)"
        case .transientRefreshFailure(let err): return "Temporary refresh failure: \(err.localizedDescription)"
        }
    }
}

struct OIDCTokens: Codable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let expiresIn: Int?
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

/// Serialises concurrent token refresh attempts so only one goes to the network.
private actor RefreshCoordinator {
    private var isRefreshing = false
    private var continuations: [CheckedContinuation<Bool, Never>] = []

    func acquireOrWait() async -> Bool? {
        if isRefreshing {
            return await withCheckedContinuation { cont in continuations.append(cont) }
        }
        isRefreshing = true
        return nil
    }

    func complete(success: Bool) {
        let waiters = continuations
        continuations.removeAll()
        isRefreshing = false
        for waiter in waiters { waiter.resume(returning: success) }
    }
}

// MARK: - AuthManager

/// OIDC authentication manager for GT3 Companion.
///
/// Uses PKCE + `ASWebAuthenticationSession` to sign in via the FluxHaus Authentik instance.
/// Tokens are stored in the Keychain and refreshed automatically before expiry.
class AuthManager: ObservableObject, @unchecked Sendable {
    static let shared = AuthManager()

    // OIDC configuration — override via Info.plist keys OIDCIssuerBase / OIDCClientID
    private static let issuerBase: String = {
        Bundle.main.object(forInfoDictionaryKey: "OIDCIssuerBase") as? String
            ?? "https://auth.fluxhaus.io/application/o/fluxhaus-server"
    }()
    static var authorizeURL: String {
        guard let base = URL(string: issuerBase) else { return issuerBase }
        return base.deletingLastPathComponent().appendingPathComponent("authorize").absoluteString + "/"
    }
    static var tokenURL: String {
        guard let base = URL(string: issuerBase) else { return issuerBase }
        return base.deletingLastPathComponent().appendingPathComponent("token").absoluteString + "/"
    }
    static let clientID: String = {
        Bundle.main.object(forInfoDictionaryKey: "OIDCClientID") as? String ?? "gt3companion"
    }()
    static let redirectScheme = "gt3companion"
    static let redirectURI = "gt3companion://auth/callback"
    static let scopes = "openid email profile offline_access"

    enum AuthState {
        case unknown
        case signedIn
        case signedOut
    }

    @Published var authState: AuthState = .unknown

    private var currentSession: ASWebAuthenticationSession?
    private var anchorProvider: AuthAnchorProvider?
    private let refreshCoordinator = RefreshCoordinator()

    var isSignedIn: Bool {
        if case .signedIn = authState { return true }
        return false
    }

    private init() {
        if getAccessToken() != nil {
            authState = .signedIn
            logger.info("Init: signed in (token in keychain)")
        } else {
            authState = .signedOut
            logger.info("Init: no token found, signedOut")
        }
    }

    // MARK: - Authorization Header

    /// Returns `Authorization: Bearer <token>` for API requests, or nil if not signed in.
    func authorizationHeader() -> String? {
        guard let token = getAccessToken() else {
            logger.warning("authorizationHeader: no access token available")
            return nil
        }
        return "Bearer \(token)"
    }

    // MARK: - Sign In

    @MainActor func signInWithOIDC() async throws {
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        let state = generateRandomString()
        let nonce = generateRandomString()

        var components = URLComponents(string: Self.authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let authURL = components.url else { throw AuthError.unknown }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: Self.redirectScheme
            ) { @Sendable url, error in
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.cancelled)
                } else if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: AuthError.unknown)
                }
            }
            session.prefersEphemeralWebBrowserSession = false
            let provider = AuthAnchorProvider()
            session.presentationContextProvider = provider
            anchorProvider = provider
            currentSession = session
            session.start()
        }
        currentSession = nil
        anchorProvider = nil

        let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        guard let code = callbackComponents?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.noCode
        }
        let returnedState = callbackComponents?.queryItems?.first(where: { $0.name == "state" })?.value
        guard returnedState == state else {
            logger.error("OIDC state mismatch")
            throw AuthError.unknown
        }

        let tokens = try await exchangeCode(code, verifier: verifier)
        storeTokens(tokens)
        authState = .signedIn
        logger.info("Signed in via OIDC")
    }

    // MARK: - Sign Out

    @MainActor func signOut() {
        deleteKeychainItem(account: "oidc_access_token")
        deleteKeychainItem(account: "oidc_refresh_token")
        deleteKeychainItem(account: "oidc_token_expiry")
        authState = .signedOut
        logger.info("Signed out")
    }

    // MARK: - Token Management

    func getAccessToken() -> String? {
        getKeychainItem(account: "oidc_access_token")
    }

    func isTokenExpiringSoon(margin: TimeInterval = 60) -> Bool {
        guard getAccessToken() != nil else { return false }
        guard let expiryStr = getKeychainItem(account: "oidc_token_expiry"),
              let interval = TimeInterval(expiryStr) else { return true }
        return Date().addingTimeInterval(margin) >= Date(timeIntervalSince1970: interval)
    }

    /// Ensures the access token is valid, refreshing proactively if near expiry.
    /// Returns `true` if a valid token is available afterward.
    ///
    /// Signs the user out only if the server **definitively rejects** the refresh token
    /// (4xx response — token has been revoked or has truly expired server-side).
    /// Transient network failures are tolerated silently — the user stays signed in.
    func ensureValidToken() async -> Bool {
        await restoreStateIfNeeded()
        guard getAccessToken() != nil else { return false }
        guard isTokenExpiringSoon() else { return true }
        logger.debug("ensureValidToken: refreshing proactively")
        return await refreshTokenIfNeeded()
    }

    @MainActor func restoreStateIfNeeded() {
        guard !isSignedIn else { return }
        if getAccessToken() != nil { authState = .signedIn }
    }

    func refreshTokenIfNeeded() async -> Bool {
        if let coalesced = await refreshCoordinator.acquireOrWait() { return coalesced }
        guard let refreshToken = getKeychainItem(account: "oidc_refresh_token") else {
            logger.warning("refreshTokenIfNeeded: no refresh token")
            await refreshCoordinator.complete(success: false)
            return false
        }
        do {
            let tokens = try await refreshAccessToken(refreshToken)
            storeTokens(tokens)
            logger.info("Token refreshed (expiresIn=\(tokens.expiresIn ?? -1))")
            await refreshCoordinator.complete(success: true)
            return true
        } catch AuthError.refreshTokenInvalid(let reason) {
            // Server explicitly rejected the token — the session is definitively dead.
            logger.error("Refresh token rejected by server — signing out: \(reason)")
            await refreshCoordinator.complete(success: false)
            await MainActor.run { signOut() }
            return false
        } catch {
            // Transient failure (no network, DNS, 5xx). Keep the session alive.
            logger.warning("Refresh failed transiently, keeping session: \(error.localizedDescription)")
            await refreshCoordinator.complete(success: false)
            return false
        }
    }

    // MARK: - Token Exchange

    private func exchangeCode(_ code: String, verifier: String) async throws -> OIDCTokens {
        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let params: [(String, String)] = [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", Self.redirectURI),
            ("client_id", Self.clientID),
            ("code_verifier", verifier),
            ("scope", Self.scopes)
        ]
        request.httpBody = Self.formEncode(params).data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw AuthError.tokenExchangeFailed(body)
        }
        return try JSONDecoder().decode(OIDCTokens.self, from: data)
    }

    private func refreshAccessToken(_ refreshToken: String) async throws -> OIDCTokens {
        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let params: [(String, String)] = [
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", Self.clientID),
            ("scope", Self.scopes)
        ]
        request.httpBody = Self.formEncode(params).data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            // Network-level failure (no connectivity, DNS, timeout). Session should survive.
            throw AuthError.transientRefreshFailure(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AuthError.transientRefreshFailure(URLError(.badServerResponse))
        }

        if http.statusCode == 200 {
            return try JSONDecoder().decode(OIDCTokens.self, from: data)
        }

        let body = String(data: data, encoding: .utf8) ?? "unknown"

        // 4xx means the server explicitly rejected our refresh token — the session is dead.
        // 5xx / other are transient server issues — keep the session alive and retry later.
        if (400...499).contains(http.statusCode) {
            logger.error("Refresh token rejected by server (\(http.statusCode)): \(body)")
            throw AuthError.refreshTokenInvalid(body)
        } else {
            logger.warning("Refresh request failed transiently (\(http.statusCode)): \(body)")
            throw AuthError.transientRefreshFailure(URLError(.badServerResponse))
        }
    }

    private func storeTokens(_ tokens: OIDCTokens) {
        setKeychainItem(account: "oidc_access_token", value: tokens.accessToken)
        if let refresh = tokens.refreshToken {
            setKeychainItem(account: "oidc_refresh_token", value: refresh)
        }
        if let expiresIn = tokens.expiresIn {
            let expiry = Date().addingTimeInterval(TimeInterval(expiresIn))
            setKeychainItem(account: "oidc_token_expiry", value: String(expiry.timeIntervalSince1970))
        } else {
            deleteKeychainItem(account: "oidc_token_expiry")
            logger.warning("storeTokens: no expiresIn — cannot track expiry")
        }
    }

    // MARK: - Keychain

    private static let keychainService = "org.davidjensenius.GT3Companion.oidc"

    private func setKeychainItem(account: String, value: String) {
        deleteKeychainItem(account: account)
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: value.data(using: .utf8)!
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status != noErr { logger.error("Keychain write failed for \(account): \(status)") }
    }

    private func getKeychainItem(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == noErr, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKeychainItem(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - PKCE helpers

    private static func formEncode(_ params: [(String, String)]) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return params.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedVal = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedVal)"
        }.joined(separator: "&")
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeVerifier() -> String {
        var buf = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buf.count, &buf)
        return Self.base64URLEncode(Data(buf))
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        Self.base64URLEncode(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private func generateRandomString() -> String {
        var buf = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buf.count, &buf)
        return Self.base64URLEncode(Data(buf))
    }
}
