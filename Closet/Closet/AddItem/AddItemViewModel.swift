import Foundation
import PostgREST
import Supabase
import UIKit

enum SaveState: Equatable {
    case pending
    case saving
    case saved
    case failed(String)
}

struct DraftItem: Identifiable {
    let id = UUID()
    var image: UIImage
    var category: ItemCategory?
    var size: String = ""
    var color: String = ""
    var occasionTags: String = ""
    var caption: String = ""
    var saveState: SaveState = .pending
}

@Observable
final class AddItemViewModel {
    var draftItems: [DraftItem] = []
    private var defaultSizes: [String: String] = [:]

    private let client = SupabaseService.shared

    func loadDefaultSizes(userID: UUID) async {
        struct SizesRow: Decodable { let sizes: [String: String] }
        let row: SizesRow? = try? await client
            .from("users")
            .select("sizes")
            .eq("id", value: userID)
            .single()
            .execute()
            .value
        defaultSizes = row?.sizes ?? [:]
    }

    func startTagging(images: [UIImage]) {
        draftItems = images.map { DraftItem(image: $0) }
    }

    func selectCategory(_ category: ItemCategory, forItemAt index: Int) {
        draftItems[index].category = category
        if draftItems[index].size.isEmpty {
            draftItems[index].size = defaultSize(for: category)
        }
    }

    private func defaultSize(for category: ItemCategory) -> String {
        switch category {
        case .top: return defaultSizes["top"] ?? ""
        case .bottom: return defaultSizes["bottom"] ?? ""
        case .shoes: return defaultSizes["shoe"] ?? ""
        case .dress, .outerwear, .accessory: return ""
        }
    }
}
