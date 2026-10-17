import Foundation
import Observation

/// Loads the merchant catalog (bundled seed -> on-disk cache -> GitHub) and
/// answers searches over the businesses that accept the user's cards.
@Observable
final class CatalogStore {
    static let shared = CatalogStore()

    static let remoteBase = URL(string: "https://raw.githubusercontent.com/shmuel2023/giftwallet/main/data/")!
    private static let refreshInterval: TimeInterval = 12 * 3600

    private(set) var cards: [Card] = []
    private(set) var merchants: [Merchant] = []
    /// Businesses accepting at least one selected card, sorted by name.
    private(set) var brands: [Brand] = []
    private(set) var categories: [String] = []
    private(set) var dataDate: Date?
    private(set) var isRefreshing = false
    private(set) var lastError: String?

    private var byKey: [String: Brand] = [:]

    private init() {
        loadLocal()
    }

    // MARK: Loading

    private var cacheDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("catalog", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func loadLocal() {
        let fm = FileManager.default
        func source(_ name: String) -> URL? {
            let cached = cacheDir.appendingPathComponent(name)
            if fm.fileExists(atPath: cached.path) { return cached }
            return Bundle.main.url(forResource: name.replacingOccurrences(of: ".json", with: ""),
                                   withExtension: "json")
        }
        guard let mURL = source("merchants.json"), let cURL = source("cards.json"),
              let mData = try? Data(contentsOf: mURL), let cData = try? Data(contentsOf: cURL)
        else { return }
        apply(merchantsData: mData, cardsData: cData)
        dataDate = (try? mURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if mURL.path.hasPrefix(Bundle.main.bundlePath) { dataDate = nil }
    }

    @discardableResult
    private func apply(merchantsData: Data, cardsData: Data) -> Bool {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        guard let m = try? dec.decode([Merchant].self, from: merchantsData),
              let c = try? dec.decode([Card].self, from: cardsData), !m.isEmpty
        else { return false }
        merchants = m
        cards = c
        rebuild()
        return true
    }

    /// Download fresh data from GitHub if the local copy is old.
    @MainActor
    func refresh(force: Bool = false) async {
        if isRefreshing { return }
        if !force, let dataDate, Date().timeIntervalSince(dataDate) < Self.refreshInterval { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let cfg = URLSessionConfiguration.default
            cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
            let session = URLSession(configuration: cfg)
            async let m = session.data(from: Self.remoteBase.appendingPathComponent("merchants.json"))
            async let c = session.data(from: Self.remoteBase.appendingPathComponent("cards.json"))
            let (mData, _) = try await m
            let (cData, _) = try await c
            guard apply(merchantsData: mData, cardsData: cData) else {
                lastError = "הנתונים שהתקבלו לא תקינים"
                return
            }
            try mData.write(to: cacheDir.appendingPathComponent("merchants.json"), options: .atomic)
            try cData.write(to: cacheDir.appendingPathComponent("cards.json"), options: .atomic)
            dataDate = .now
            lastError = nil
        } catch {
            lastError = "אין חיבור לעדכון הנתונים"
        }
    }

    // MARK: Index

    /// Re-group businesses for the currently selected cards.
    func rebuild() {
        let selected = AppSettings.shared.selectedCards
        let relevant = merchants.filter { selected.isEmpty || selected.contains($0.card) }
        let grouped = Dictionary(grouping: relevant, by: \.brandKey)
        brands = grouped.map { Brand(key: $0.key, entries: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        byKey = Dictionary(uniqueKeysWithValues: brands.map { ($0.key, $0) })
        var counts: [String: Int] = [:]
        for b in brands { if let c = b.primary.category { counts[c, default: 0] += 1 } }
        categories = counts.sorted { $0.value > $1.value }.map(\.key)
    }

    func brand(_ key: String) -> Brand? { byKey[key] }

    /// All brand keys (any card) - used to tell "FOX" from "FOX HOME" on the map.
    var allKeys: [String] { Array(Set(merchants.map(\.brandKey))) }

    // MARK: Search

    /// Search by business name, brand, product words (BuyMe's search terms
    /// such as "נעלי ספורט", "סושי") and category. All words must match.
    func search(_ query: String, category: String? = nil, cardId: String? = nil) -> [Brand] {
        var pool = brands
        if let category { pool = pool.filter { $0.primary.category == category } }
        if let cardId { pool = pool.filter { $0.cardIds.contains(cardId) } }
        let tokens = query.searchNormalized.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return pool }

        var scored: [(Brand, Int)] = []
        for b in pool {
            var total = 0
            var allMatched = true
            for t in tokens {
                let s: Int
                if b.nameNorm.hasPrefix(t) { s = 10 }
                else if b.nameNorm.contains(t) { s = 7 }
                else if b.termsNorm.contains(t) { s = 4 }
                else if b.metaNorm.contains(t) { s = 3 }
                else if t.count > 3, b.termsNorm.contains(String(t.dropLast())) { s = 2 } // נעליים -> נעלי
                else { s = 0 }
                if s == 0 { allMatched = false; break }
                total += s
            }
            if allMatched { scored.append((b, total)) }
        }
        return scored.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// Businesses that fit a wish-list item: the ones the user pinned, or the
    /// best automatic matches for its text (physical stores only).
    func matches(for item: WishItem, limit: Int = 6) -> [Brand] {
        if !item.brandKeys.isEmpty { return item.brandKeys.compactMap { byKey[$0] } }
        return Array(search(item.title).filter { !$0.isOnlineOnly }.prefix(limit))
    }
}
