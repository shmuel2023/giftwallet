import Foundation
import MapKit

/// A physical place where a brand can be visited.
struct Branch: Identifiable, Hashable {
    let id: String
    let brandKey: String
    let name: String
    let address: String?
    let coordinate: CLLocationCoordinate2D
    let distance: CLLocationDistance

    static func == (a: Branch, b: Branch) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    var distanceText: String {
        distance < 1000 ? "\(Int(distance / 10) * 10) מ׳" : String(format: "%.1f ק״מ", distance / 1000)
    }

    func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        item.openInMaps(launchOptions: nil)
    }
}

/// Finds the nearest branches of a business. Single-location businesses use
/// the coordinates from the harvester; chains are looked up live in Apple Maps.
enum BranchFinder {
    static func branches(of brand: Brand, near location: CLLocation,
                         radius: CLLocationDistance = 3000, limit: Int = 5) async -> [Branch] {
        if let c = brand.coordinate {
            let d = location.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            guard d <= radius * 3 else { return [] }   // destination businesses: allow a bit further
            return [Branch(id: brand.key, brandKey: brand.key, name: brand.name,
                           address: brand.primary.address, coordinate: c, distance: d)]
        }
        guard brand.isChain else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = brand.mapQuery
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(center: location.coordinate,
                                            latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }

        let keys = CatalogStore.shared.allKeys
        let results: [Branch] = response.mapItems.compactMap { item in
            guard let name = item.name, matches(name, brand: brand, allKeys: keys) else { return nil }
            let c = item.placemark.coordinate
            let d = location.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            guard d <= radius else { return nil }
            return Branch(id: "\(brand.key)@\(String(format: "%.5f,%.5f", c.latitude, c.longitude))",
                          brandKey: brand.key, name: name,
                          address: item.placemark.title, coordinate: c, distance: d)
        }
        return Array(results.sorted { $0.distance < $1.distance }.prefix(limit))
    }

    /// "What can I use here?" - the stores and restaurants around the user
    /// (e.g. inside a mall) that accept one of the user's cards.
    static func acceptingPlacesHere(near location: CLLocation,
                                    radius: CLLocationDistance = 400) async -> [(Brand, Branch)] {
        let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: radius)
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        let catalog = CatalogStore.shared
        let keys = catalog.allKeys
        var out: [(Brand, Branch)] = []
        var seen = Set<String>()
        for item in response.mapItems {
            guard let name = item.name else { continue }
            // longest matching brand name wins
            let candidates = catalog.brands.filter { b in
                b.mapQuery.count >= 3 && matches(name, brand: b, allKeys: keys)
            }
            guard let brand = candidates.max(by: { $0.mapQuery.count < $1.mapQuery.count }) else { continue }
            let c = item.placemark.coordinate
            let d = location.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            let branch = Branch(id: "\(brand.key)@\(String(format: "%.5f,%.5f", c.latitude, c.longitude))",
                                brandKey: brand.key, name: name, address: item.placemark.title,
                                coordinate: c, distance: d)
            if seen.insert(branch.id).inserted { out.append((brand, branch)) }
        }
        return out.sorted { $0.1.distance < $1.1.distance }
    }

    /// Is this Apple Maps result really this brand? ("FOX HOME" is not "FOX".)
    static func matches(_ placeName: String, brand: Brand, allKeys: [String]) -> Bool {
        let place = placeName.searchNormalized
        let key = brand.mapQuery.searchNormalized
        guard !key.isEmpty, place.contains(key) else { return false }
        // a longer, different brand name that also fits wins
        return !allKeys.contains { other in
            other.count > key.count && other.contains(key) && place.contains(other.searchNormalized)
        }
    }
}
