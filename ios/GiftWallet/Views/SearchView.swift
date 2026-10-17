import SwiftUI

struct SearchView: View {
    /// When set, shows only businesses accepting this card (opened from a voucher).
    var cardFilter: String? = nil
    var embedded = false

    @State private var query = ""
    @State private var category: String?
    @State private var path: [Brand] = []
    @Bindable private var router = Router.shared

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack(path: $path) {
                content
                    .navigationDestination(for: Brand.self) { BrandDetailView(brand: $0) }
            }
            .onChange(of: router.pendingBrandKey, initial: true) { _, key in
                guard let key, let b = CatalogStore.shared.brand(key) else { return }
                path = [b]
                router.pendingBrandKey = nil
            }
        }
    }

    private var content: some View {
        let catalog = CatalogStore.shared
        let results = catalog.search(query, category: category, cardId: cardFilter)
        return List {
            if query.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip("הכול", selected: category == nil) { category = nil }
                            ForEach(catalog.categories, id: \.self) { c in
                                chip(c, selected: category == c) { category = (category == c ? nil : c) }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            Section {
                ForEach(results) { b in
                    NavigationLink(value: b) { BrandRow(brand: b) }
                }
            } header: {
                Text(results.isEmpty ? "לא נמצאו עסקים" : "\(results.count) עסקים")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(cardFilter.map { "איפה לממש \(CardStyle.shortName($0))" } ?? "איפה לממש")
        .searchable(text: $query, prompt: "מוצר, מותג או חנות")
        .overlay {
            if catalog.brands.isEmpty {
                ContentUnavailableView("אין נתונים עדיין", systemImage: "arrow.down.circle",
                                       description: Text("בחר/י כרטיסים בהגדרות ובדוק/י חיבור לאינטרנט"))
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(selected ? Color.accentColor : Color(.secondarySystemGroupedBackground), in: Capsule())
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
