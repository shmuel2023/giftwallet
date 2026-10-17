import Foundation
import CoreLocation
import SwiftUI

/// A gift card the app supports (from data/cards.json).
struct Card: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let issuer: String
    let sourceUrl: String?
    let terms: String?
    let merchantCount: Int?
}

/// One business accepting one card (from data/merchants.json).
struct Merchant: Codable, Identifiable, Hashable {
    let id: String
    let card: String
    let name: String
    let brandKey: String
    let category: String?
    let subcategories: [String]
    let regions: [String]
    let searchTerms: [String]
    let isChain: Bool
    let onlineRedeem: Bool
    let address: String?
    let lat: Double?
    let lng: Double?
    let phone: String?
    let website: String?
    let branchLocatorUrl: String?
    let reservationUrl: String?
    let logoUrl: String?
    let slogan: String?
    let terms: String
}

/// A business as the user sees it: the same brand merged across all of the
/// user's cards (e.g. FOX accepts both BUYME ALL and DREAM CARD).
struct Brand: Identifiable, Hashable {
    let key: String
    let entries: [Merchant]

    // precomputed, normalized text for fast search
    let nameNorm: String
    let termsNorm: String
    let metaNorm: String

    init(key: String, entries: [Merchant]) {
        self.key = key
        // BuyMe entries carry richer details - show them first
        self.entries = entries.sorted { a, b in
            a.card.hasPrefix("buyme") && !b.card.hasPrefix("buyme")
        }
        let p = self.entries[0]
        nameNorm = ([p.name, key] + self.entries.map(\.name)).joined(separator: " | ").searchNormalized
        termsNorm = self.entries.flatMap(\.searchTerms).joined(separator: " | ").searchNormalized
        metaNorm = ([p.slogan ?? "", p.category ?? ""] + self.entries.flatMap(\.subcategories))
            .joined(separator: " | ").searchNormalized
    }

    var id: String { key }
    var primary: Merchant { entries[0] }
    var name: String { primary.name }
    var cardIds: [String] { entries.map(\.card) }
    var isChain: Bool { entries.contains { $0.isChain } }
    var onlineRedeem: Bool { entries.contains { $0.onlineRedeem } }
    var subtitle: String? { primary.slogan ?? primary.category }

    var coordinate: CLLocationCoordinate2D? {
        guard let m = entries.first(where: { $0.lat != nil && $0.lng != nil }),
              let lat = m.lat, let lng = m.lng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    /// Only redeemable online - no physical store to walk into.
    var isOnlineOnly: Bool {
        onlineRedeem && !isChain && primary.address == nil && primary.regions.isEmpty
    }

    /// What to type into Apple Maps to find this brand's branches.
    var mapQuery: String {
        let latin = key.range(of: "[a-z]", options: .regularExpression) != nil
        if latin { return key }
        return name
            .replacingOccurrences(of: "סניפים נבחרים ברשת", with: "")
            .replacingOccurrences(of: "סניפים נבחרים של", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Card styling

enum CardStyle {
    static func color(_ cardId: String) -> Color {
        switch cardId {
        case let id where id.hasPrefix("buyme"): return Color(red: 1.0, green: 0.55, blue: 0.0)
        case "dreamcard": return Color(red: 0.45, green: 0.25, blue: 0.85)
        default: return .gray
        }
    }

    static func shortName(_ cardId: String) -> String {
        switch cardId {
        case "buyme_all": return "BUYME ALL"
        case "dreamcard": return "DREAM CARD"
        case "other": return "אחר"
        default: return cardId
        }
    }
}

// MARK: - Search normalization

extension String {
    /// Lowercased, without niqqud / accents, with unified quote marks.
    var searchNormalized: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "׳", with: "'")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "״", with: "\"")
            .replacingOccurrences(of: "-", with: " ")
    }
}
