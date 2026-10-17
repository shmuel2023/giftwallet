import Foundation
import Observation

/// User preferences, persisted in UserDefaults.
@Observable
final class AppSettings {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    var selectedCards: Set<String> {
        didSet { d.set(Array(selectedCards), forKey: "selectedCards"); CatalogStore.shared.rebuild() }
    }
    var onboarded: Bool { didSet { d.set(onboarded, forKey: "onboarded") } }
    var locationAlerts: Bool { didSet { d.set(locationAlerts, forKey: "locationAlerts") } }
    var expiryReminders: Bool { didSet { d.set(expiryReminders, forKey: "expiryReminders") } }

    private init() {
        selectedCards = Set(d.stringArray(forKey: "selectedCards") ?? [])
        onboarded = d.bool(forKey: "onboarded")
        locationAlerts = d.object(forKey: "locationAlerts") as? Bool ?? true
        expiryReminders = d.object(forKey: "expiryReminders") as? Bool ?? true
    }
}
