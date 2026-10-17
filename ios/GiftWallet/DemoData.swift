#if DEBUG
import Foundation
import SwiftData

/// Development only: launch with `-gwDemo YES` to fill the app with sample
/// data for testing in the simulator. Never compiled into release builds.
enum DemoData {
    @MainActor
    static func seedIfRequested(_ container: ModelContainer) {
        guard UserDefaults.standard.bool(forKey: "gwDemo") else { return }
        let ctx = container.mainContext
        let existing = (try? ctx.fetchCount(FetchDescriptor<WishItem>())) ?? 0
        guard existing == 0 else { return }
        let cal = Calendar.current
        ctx.insert(WishItem(title: "נעלי ריצה", note: "מידה 43"))
        ctx.insert(WishItem(title: "ג'ינס", brandKeys: ["american eagle"]))
        ctx.insert(WishItem(title: "סושי"))
        ctx.insert(Voucher(cardId: "buyme_all", title: "מתנה מהעבודה", balance: 400,
                           expiry: cal.date(byAdding: .day, value: 21, to: .now), code: "1234567890123456"))
        ctx.insert(Voucher(cardId: "dreamcard", title: "יום הולדת", balance: 250,
                           expiry: cal.date(byAdding: .year, value: 3, to: .now)))
        try? ctx.save()
    }
}
#endif
