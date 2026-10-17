import Foundation
import CoreLocation
import SwiftData
import UserNotifications

/// Background "you're near a store" alerts.
///
/// iOS lets an app watch at most 20 geographic regions. So we:
/// 1. watch significant location changes (wakes the app every ~500 m of travel),
/// 2. on each wake, find the nearest branches of businesses that matter
///    (wish-list matches + businesses tied to a voucher),
/// 3. watch a 150 m circle around each of the 19 nearest, plus one larger
///    circle around the user that triggers the next refresh when left.
final class LocationAlerts: NSObject, CLLocationManagerDelegate {
    static let shared = LocationAlerts()

    private let manager = CLLocationManager()
    var container: ModelContainer?

    private let regionPrefix = "gw."
    private let refreshRegionId = "gw.refresh"
    private let storeRadius: CLLocationDistance = 150
    private let defaults = UserDefaults.standard
    private var lastRefresh: Date = .distantPast
    private var refreshing = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var authorization: CLAuthorizationStatus { manager.authorizationStatus }

    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        default: break
        }
    }

    /// Call on launch and whenever the wish list / vouchers / settings change.
    func start() {
        guard AppSettings.shared.locationAlerts else { stop(); return }
        let status = manager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        }
        manager.requestLocation()
    }

    func stop() {
        manager.stopMonitoringSignificantLocationChanges()
        for r in manager.monitoredRegions where r.identifier.hasPrefix(regionPrefix) {
            manager.stopMonitoring(for: r)
        }
    }

    /// Force the next location update to rebuild the watched stores.
    func invalidate() {
        lastRefresh = .distantPast
        start()
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()   // needed for alerts while the app is closed
        }
        start()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in await self.rebuildRegions(around: loc) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier != refreshRegionId, region.identifier.hasPrefix(regionPrefix) else { return }
        Task { @MainActor in self.notifyArrival(regionId: region.identifier) }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        if region.identifier == refreshRegionId { manager.requestLocation() }
    }

    // MARK: Watched stores

    @MainActor
    private func rebuildRegions(around location: CLLocation) async {
        guard AppSettings.shared.locationAlerts, !refreshing,
              Date().timeIntervalSince(lastRefresh) > 5 * 60 else { return }
        refreshing = true
        defer { refreshing = false }
        lastRefresh = .now

        let targets = targetBrands()
        var branches: [Branch] = []
        for brand in targets.prefix(15) {   // Apple Maps rate limits: keep it small
            branches += await BranchFinder.branches(of: brand, near: location, radius: 4000, limit: 3)
        }
        let nearest = branches.sorted { $0.distance < $1.distance }.prefix(19)

        for r in manager.monitoredRegions where r.identifier.hasPrefix(regionPrefix) {
            manager.stopMonitoring(for: r)
        }
        var names: [String: [String]] = [:]
        for b in nearest {
            let id = regionPrefix + b.id
            let region = CLCircularRegion(center: b.coordinate, radius: storeRadius, identifier: id)
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
            names[id] = [b.brandKey, b.name]
        }
        defaults.set(names, forKey: "gw.regionNames")

        let refresh = CLCircularRegion(center: location.coordinate, radius: 1500, identifier: refreshRegionId)
        refresh.notifyOnEntry = false
        refresh.notifyOnExit = true
        manager.startMonitoring(for: refresh)
    }

    /// Businesses worth an alert: wish-list matches and businesses a voucher is tied to.
    @MainActor
    private func targetBrands() -> [Brand] {
        guard let container else { return [] }
        let ctx = ModelContext(container)
        let catalog = CatalogStore.shared
        var keys: [String] = []
        let wishes = (try? ctx.fetch(FetchDescriptor<WishItem>(predicate: #Predicate { !$0.done }))) ?? []
        for w in wishes { keys += catalog.matches(for: w, limit: 4).map(\.key) }
        let vouchers = (try? ctx.fetch(FetchDescriptor<Voucher>(predicate: #Predicate { !$0.archived }))) ?? []
        keys += vouchers.filter(\.isUsable).compactMap(\.brandKey)
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }.compactMap { catalog.brand($0) }
    }

    // MARK: Notification

    @MainActor
    private func notifyArrival(regionId: String) {
        guard let container,
              let info = (defaults.dictionary(forKey: "gw.regionNames") as? [String: [String]])?[regionId],
              info.count == 2, let brand = CatalogStore.shared.brand(info[0]) else { return }

        // at most one alert per business every 4 hours
        var lastSent = defaults.dictionary(forKey: "gw.lastSent") as? [String: Double] ?? [:]
        if let t = lastSent[brand.key], Date().timeIntervalSince1970 - t < 4 * 3600 { return }

        let ctx = ModelContext(container)
        let wishes = (try? ctx.fetch(FetchDescriptor<WishItem>(predicate: #Predicate { !$0.done }))) ?? []
        let wanted = wishes.filter { w in CatalogStore.shared.matches(for: w).contains { $0.key == brand.key } }
        let vouchers = ((try? ctx.fetch(FetchDescriptor<Voucher>())) ?? []).filter { $0.isUsable && $0.accepts(brand) }
        guard !wanted.isEmpty || !vouchers.isEmpty else { return }

        var lines: [String] = []
        if !wanted.isEmpty {
            lines.append("מהרשימה שלך: " + wanted.map(\.title).joined(separator: ", "))
        }
        if !vouchers.isEmpty {
            let total = vouchers.reduce(0) { $0 + $1.balance }
            let cards = Set(vouchers.map { CardStyle.shortName($0.cardId) }).sorted().joined(separator: " + ")
            lines.append("אפשר לשלם עם \(cards) · יתרה \(total.shekels)")
        }

        let content = UNMutableNotificationContent()
        content.title = "📍 \(info[1]) ממש קרוב"
        content.body = lines.joined(separator: "\n")
        content.sound = .default
        content.userInfo = ["brandKey": brand.key]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "arrive.\(brand.key)", content: content, trigger: nil))

        lastSent[brand.key] = Date().timeIntervalSince1970
        defaults.set(lastSent, forKey: "gw.lastSent")
    }
}
