import Foundation
import SwiftData

/// A gift voucher the user holds.
@Model
final class Voucher {
    var cardId: String          // "buyme_all", "dreamcard" or "other"
    var title: String
    var balance: Double
    var expiry: Date?
    var code: String
    var note: String
    var brandKey: String?       // set when the voucher is for one specific business
    var archived: Bool
    var createdAt: Date

    init(cardId: String, title: String = "", balance: Double = 0, expiry: Date? = nil,
         code: String = "", note: String = "", brandKey: String? = nil) {
        self.cardId = cardId
        self.title = title
        self.balance = balance
        self.expiry = expiry
        self.code = code
        self.note = note
        self.brandKey = brandKey
        self.archived = false
        self.createdAt = .now
    }

    var displayTitle: String {
        title.isEmpty ? CardStyle.shortName(cardId) : title
    }

    var daysLeft: Int? {
        guard let expiry else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now),
                                               to: Calendar.current.startOfDay(for: expiry)).day
    }

    var isUsable: Bool {
        !archived && balance > 0 && (daysLeft ?? 1) >= 0
    }

    /// Can this voucher be used at the given business?
    func accepts(_ brand: Brand) -> Bool {
        if let brandKey { return brandKey == brand.key }
        return brand.cardIds.contains(cardId)
    }
}

/// Something the user wants to buy soon.
@Model
final class WishItem {
    var title: String
    var note: String
    /// Businesses the user picked. Empty = match automatically by the title.
    var brandKeys: [String]
    var done: Bool
    var createdAt: Date

    init(title: String, note: String = "", brandKeys: [String] = []) {
        self.title = title
        self.note = note
        self.brandKeys = brandKeys
        self.done = false
        self.createdAt = .now
    }
}

extension Double {
    var shekels: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = self.rounded() == self ? 0 : 2
        return "₪" + (f.string(from: NSNumber(value: self)) ?? "\(self)")
    }
}
