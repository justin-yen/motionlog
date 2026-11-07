import Foundation

struct AppConfiguration: Sendable {
    let supabaseURL: URL?
    let supabaseAnonKey: String?
    let useMockData: Bool

    static let current = AppConfiguration(
        supabaseURL: Bundle.main.string(forInfoKey: "SUPABASE_URL").flatMap(URL.init(string:)),
        supabaseAnonKey: Bundle.main.string(forInfoKey: "SUPABASE_ANON_KEY"),
        useMockData: Bundle.main.string(forInfoKey: "PT_USE_MOCK_DATA") != "NO"
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
