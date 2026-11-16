import Foundation

struct AppConfiguration: Sendable {
    let supabaseURL: URL?
    let supabaseAnonKey: String?
    let useMockData: Bool
    let authTestPhone: String?
    let authTestCode: String?

    static let current = AppConfiguration(
        supabaseURL: Bundle.main.string(forInfoKey: "SUPABASE_URL").flatMap(URL.init(string:)),
        supabaseAnonKey: Bundle.main.string(forInfoKey: "SUPABASE_ANON_KEY"),
        useMockData: Bundle.main.string(forInfoKey: "PT_USE_MOCK_DATA") != "NO",
        authTestPhone: Bundle.main.string(forInfoKey: "AUTH_TEST_PHONE"),
        authTestCode: Bundle.main.string(forInfoKey: "AUTH_TEST_CODE")
    )
}

private extension Bundle {
    func string(forInfoKey key: String) -> String? {
        guard let value = object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.contains("$(") else { return nil }
        return value
    }
}
