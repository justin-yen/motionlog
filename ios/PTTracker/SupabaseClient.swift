import Foundation
import Security

enum ClientError: LocalizedError {
    case missingConfiguration
    case invalidResponse
    case sessionExpired
    case server(message: String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration: "Supabase is not configured."
        case .invalidResponse: "The server returned an unexpected response."
        case .sessionExpired: "Your session expired. Please sign in again."
        case .server(let message): message
        }
    }
}

actor SupabaseClient {
    private let baseURL: URL
    private let anonKey: String
    private let urlSession: URLSession
    private(set) var session: AuthSession?
    private var refreshTask: Task<AuthSession, Error>?

    init(baseURL: URL, anonKey: String, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.urlSession = urlSession
        self.session = KeychainStore.loadSession()
    }

    func requestOTP(phone: String) async throws {
        let body = ["phone": phone, "create_user": true] as [String: Any]
        _ = try await request(path: "/auth/v1/otp", method: "POST", body: body, authenticated: false)
    }

    func verifyOTP(phone: String, code: String) async throws -> AuthSession {
        let body: [String: Any] = ["phone": phone, "token": code, "type": "sms"]
        let data = try await request(path: "/auth/v1/verify", method: "POST", body: body, authenticated: false)
        let response = try JSONDecoder().decode(VerifyResponse.self, from: data)
        let newSession = AuthSession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            userID: response.user.id
        )
        session = newSession
        try KeychainStore.save(session: newSession)
        return newSession
    }

    func signOut() {
        session = nil
        KeychainStore.deleteSession()
    }

    func rest(path: String, method: String = "GET", body: Any? = nil, prefer: String? = nil) async throws -> Data {
        try await request(path: "/rest/v1/\(path)", method: method, body: body, authenticated: true, prefer: prefer)
    }

    func invokeFunction<Request: Encodable & Sendable>(
        _ name: String,
        body: Request
    ) async throws -> Data {
        let encodedBody = try JSONEncoder().encode(body)
        return try await request(
            path: "/functions/v1/\(name)",
            method: "POST",
            body: nil,
            rawBody: encodedBody,
            authenticated: true
        )
    }

    func uploadAudio(_ data: Data, path: String) async throws {
        try await uploadAudio(data, path: path, canRefresh: true)
    }

    private func uploadAudio(_ data: Data, path: String, canRefresh: Bool) async throws {
        guard let url = URL(string: "/storage/v1/object/session-audio/\(path)", relativeTo: baseURL),
              let session else { throw ClientError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        request.setValue("false", forHTTPHeaderField: "x-upsert")
        request.httpBody = data
        let (responseData, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        if http.statusCode == 401, canRefresh {
            _ = try await refreshSession()
            return try await uploadAudio(data, path: path, canRefresh: false)
        }
        if http.statusCode == 401 {
            signOut()
            throw ClientError.sessionExpired
        }
        guard 200..<300 ~= http.statusCode else {
            let payload = try? JSONDecoder().decode(ServerError.self, from: responseData)
            throw ClientError.server(
                message: payload?.message ?? payload?.error ?? "Voice-note upload failed (\(http.statusCode))."
            )
        }
    }

    private func request(
        path: String,
        method: String,
        body: Any?,
        rawBody: Data? = nil,
        authenticated: Bool,
        prefer: String? = nil,
        canRefresh: Bool = true
    ) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw ClientError.invalidResponse }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue(anonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated {
            guard let session else { throw ClientError.server(message: "Please sign in again.") }
            urlRequest.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }
        if let prefer { urlRequest.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let rawBody {
            urlRequest.httpBody = rawBody
        } else if let body {
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await urlSession.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        if authenticated, http.statusCode == 401, canRefresh {
            _ = try await refreshSession()
            return try await request(
                path: path,
                method: method,
                body: body,
                rawBody: rawBody,
                authenticated: true,
                prefer: prefer,
                canRefresh: false
            )
        }
        if authenticated, http.statusCode == 401 {
            signOut()
            throw ClientError.sessionExpired
        }
        guard 200..<300 ~= http.statusCode else {
            let payload = try? JSONDecoder().decode(ServerError.self, from: data)
            throw ClientError.server(message: payload?.message ?? payload?.error ?? "Request failed (\(http.statusCode)).")
        }
        return data
    }

    private func refreshSession() async throws -> AuthSession {
        let task: Task<AuthSession, Error>
        if let existingTask = refreshTask {
            task = existingTask
        } else {
            guard let refreshToken = session?.refreshToken else {
                signOut()
                throw ClientError.sessionExpired
            }
            let newTask = Task { [baseURL, anonKey, urlSession] in
                guard let url = URL(string: "/auth/v1/token?grant_type=refresh_token", relativeTo: baseURL) else {
                    throw ClientError.invalidResponse
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue(anonKey, forHTTPHeaderField: "apikey")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])

                let (data, response) = try await urlSession.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
                guard 200..<300 ~= http.statusCode else { throw ClientError.sessionExpired }
                let refreshed = try JSONDecoder().decode(VerifyResponse.self, from: data)
                return AuthSession(
                    accessToken: refreshed.accessToken,
                    refreshToken: refreshed.refreshToken,
                    userID: refreshed.user.id
                )
            }
            refreshTask = newTask
            task = newTask
        }

        do {
            let refreshedSession = try await task.value
            refreshTask = nil
            session = refreshedSession
            try KeychainStore.save(session: refreshedSession)
            return refreshedSession
        } catch {
            refreshTask = nil
            signOut()
            throw ClientError.sessionExpired
        }
    }
}

private struct VerifyResponse: Decodable {
    struct User: Decodable { let id: UUID }
    let accessToken: String
    let refreshToken: String
    let user: User

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
    }
}

private struct ServerError: Decodable {
    let message: String?
    let error: String?
}

enum KeychainStore {
    private static let service = "com.example.PTTracker"
    private static let account = "supabase-session"

    static func save(session: AuthSession) throws {
        let data = try JSONEncoder().encode(session)
        deleteSession()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ClientError.server(message: "Could not securely save the session.")
        }
    }

    static func loadSession() -> AuthSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    static func deleteSession() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
