import SwiftUI
import SwiftData
import MapKit

struct NearbyView: View {
    @Query(filter: #Predicate<WishItem> { !$0.done }) private var wishes: [WishItem]

    @State private var location: CLLocation?
    @State private var loading = false
    @State private var tried = false
    @State private var wishBranches: [(Brand, Branch)] = []
    @State private var here: [(Brand, Branch)] = []
    @State private var local: [(Brand, CLLocationDistance)] = []

    var body: some View {
        NavigationStack {
            List {
                if location == nil && tried && !loading {
                    ContentUnavailableView {
                        Label("אין גישה למיקום", systemImage: "location.slash")
                    } description: {
                        Text("אפשר/י גישה למיקום כדי לראות חנויות קרובות שמכבדות את הכרטיסים שלך.")
                    } actions: {
                        Button("פתח הגדרות") {
                            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                        }
                    }
                }

                if let location {
                    Section {
                        Map(initialPosition: .region(MKCoordinateRegion(center: location.coordinate,
                                                                        latitudinalMeters: 1500,
                                                                        longitudinalMeters: 1500))) {
                            UserAnnotation()
                            ForEach(wishBranches, id: \.1.id) { pair in
                                Marker(pair.1.name, systemImage: "cart.fill", coordinate: pair.1.coordinate)
                                    .tint(.green)
                            }
                            ForEach(here, id: \.1.id) { pair in
                                Marker(pair.1.name, coordinate: pair.1.coordinate)
                                    .tint(CardStyle.color(pair.0.cardIds.first ?? ""))
                            }
                        }
                        .frame(height: 220)
                        .listRowInsets(EdgeInsets())
                    }
                }

                if !wishBranches.isEmpty {
                    Section("מהרשימה שלך") {
                        ForEach(wishBranches, id: \.1.id) { pair in
                            branchRow(pair.0, pair.1, note: wishTitles(for: pair.0))
                        }
                    }
                }

                if !here.isEmpty {
                    Section("ממש כאן · מכבדים את הכרטיסים שלך") {
                        ForEach(here, id: \.1.id) { pair in branchRow(pair.0, pair.1, note: nil) }
                    }
                }

                if !local.isEmpty {
                    Section("עסקים בסביבה (עד 3 ק״מ)") {
                        ForEach(local, id: \.0.id) { pair in
                            NavigationLink(value: pair.0) {
                                BrandRow(brand: pair.0, detail: distanceText(pair.1))
                            }
                        }
                    }
                }

                if location != nil && !loading && wishBranches.isEmpty && here.isEmpty && local.isEmpty {
                    ContentUnavailableView("לא נמצאו עסקים קרובים", systemImage: "mappin.slash",
                                           description: Text("נסה/י שוב כשתהיה/י במרכז קניות"))
                }
            }
            .overlay { if loading && location == nil { ProgressView("מאתר מיקום…") } }
            .navigationTitle("קרוב אליי")
            .navigationDestination(for: Brand.self) { BrandDetailView(brand: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if loading { ProgressView() } else {
                        Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    }
                }
            }
            .refreshable { await load() }
            .task { if location == nil { await load() } }
        }
    }

    private func branchRow(_ brand: Brand, _ branch: Branch, note: String?) -> some View {
        NavigationLink(value: brand) {
            HStack {
                BrandRow(brand: brand, detail: note ?? branch.address)
                Spacer()
                Text(branch.distanceText).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func wishTitles(for brand: Brand) -> String {
        let catalog = CatalogStore.shared
        let titles = wishes.filter { w in catalog.matches(for: w).contains { $0.key == brand.key } }.map(\.title)
        return "ברשימה: " + titles.joined(separator: ", ")
    }

    private func distanceText(_ d: CLLocationDistance) -> String {
        d < 1000 ? "\(Int(d / 10) * 10) מ׳" : String(format: "%.1f ק״מ", d / 1000)
    }

    private func load() async {
        loading = true
        defer { loading = false; tried = true }
        LocationAlerts.shared.requestPermission()
        guard let loc = await CurrentLocation.get() else { return }
        location = loc
        let catalog = CatalogStore.shared

        local = catalog.brands.compactMap { b -> (Brand, CLLocationDistance)? in
            guard let c = b.coordinate else { return nil }
            let d = loc.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            return d <= 3000 ? (b, d) : nil
        }
        .sorted { $0.1 < $1.1 }
        .prefix(40).map { $0 }

        here = await BranchFinder.acceptingPlacesHere(near: loc)

        var seen = Set<String>()
        let targets = wishes.flatMap { catalog.matches(for: $0, limit: 4) }.filter { seen.insert($0.key).inserted }
        var found: [(Brand, Branch)] = []
        for b in targets.prefix(12) {
            for branch in await BranchFinder.branches(of: b, near: loc, radius: 3000, limit: 2) {
                found.append((b, branch))
            }
        }
        wishBranches = found.sorted { $0.1.distance < $1.1.distance }
    }
}
