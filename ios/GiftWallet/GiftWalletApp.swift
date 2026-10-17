import SwiftUI
import SwiftData
import UserNotifications

@main
struct GiftWalletApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Voucher.self, WishItem.self)
        } catch {
            fatalError("Could not open the local database: \(error)")
        }
        // must exist before iOS delivers a background region event
        LocationAlerts.shared.container = container
        _ = CatalogStore.shared
        #if DEBUG
        DemoData.seedIfRequested(container)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "he_IL"))
        }
        .modelContainer(container)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        LocationAlerts.shared.start()
        return true
    }

    // show alerts as banners even while the app is open
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let key = response.notification.request.content.userInfo["brandKey"] as? String {
            Task { @MainActor in Router.shared.open(brandKey: key) }
        }
        completionHandler()
    }
}

/// Lets a tapped notification open the right business.
@Observable
final class Router {
    static let shared = Router()
    var tab: Tab = .search
    var pendingBrandKey: String?

    enum Tab: String, Hashable { case search, nearby, wishlist, vouchers, settings }

    init() {
        #if DEBUG
        if let t = UserDefaults.standard.string(forKey: "gwTab"), let tab = Tab(rawValue: t) { self.tab = tab }
        pendingBrandKey = UserDefaults.standard.string(forKey: "gwBrand")
        #endif
    }

    func open(brandKey: String) {
        pendingBrandKey = brandKey
        tab = .search
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context

    var body: some View {
        Group {
            if AppSettings.shared.onboarded {
                MainTabs()
            } else {
                OnboardingView()
            }
        }
        .task { await CatalogStore.shared.refresh() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await CatalogStore.shared.refresh()
                await Reminders.reschedule(container: context.container)
            }
            LocationAlerts.shared.start()
        }
    }
}

struct MainTabs: View {
    @Bindable private var router = Router.shared

    var body: some View {
        TabView(selection: $router.tab) {
            SearchView()
                .tabItem { Label("חיפוש", systemImage: "magnifyingglass") }
                .tag(Router.Tab.search)
            NearbyView()
                .tabItem { Label("קרוב אליי", systemImage: "location.fill") }
                .tag(Router.Tab.nearby)
            WishlistView()
                .tabItem { Label("הרשימה שלי", systemImage: "checklist") }
                .tag(Router.Tab.wishlist)
            VouchersView()
                .tabItem { Label("השוברים שלי", systemImage: "wallet.pass") }
                .tag(Router.Tab.vouchers)
            SettingsView()
                .tabItem { Label("הגדרות", systemImage: "gearshape") }
                .tag(Router.Tab.settings)
        }
    }
}
