import Foundation
import Supabase

enum SupabaseService {
    static let shared = SupabaseClient(
        supabaseURL: URL(string: infoPlistValue(for: "SUPABASE_URL"))!,
        supabaseKey: infoPlistValue(for: "SUPABASE_ANON_KEY")
    )

    private static func infoPlistValue(for key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else {
            fatalError("Missing \(key) in Info.plist — check Closet/Config.xcconfig")
        }
        return value
    }
}
