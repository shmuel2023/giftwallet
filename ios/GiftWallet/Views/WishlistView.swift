import SwiftUI
import SwiftData

struct WishlistView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WishItem.createdAt, order: .reverse) private var items: [WishItem]
    @State private var showAdd = false

    var body: some View {
        let active = items.filter { !$0.done }
        let done = items.filter(\.done)

        NavigationStack {
            List {
                if items.isEmpty {
                    ContentUnavailableView {
                        Label("הרשימה ריקה", systemImage: "cart")
                    } description: {
                        Text("רשום/י מוצרים שבא לך לקנות. כשתהיה/י ליד חנות שמוכרת אותם ומכבדת את הכרטיס שלך, תקבל/י התראה.")
                    } actions: {
                        Button("הוסף מוצר") { showAdd = true }.buttonStyle(.borderedProminent)
                    }
                }
                if !active.isEmpty {
                    Section("רוצה לקנות") {
                        ForEach(active) { item in
                            NavigationLink { WishDetailView(item: item) } label: { row(item) }
                                .swipeActions(edge: .leading) {
                                    Button { item.done = true; changed() } label: {
                                        Label("נקנה", systemImage: "checkmark")
                                    }.tint(.green)
                                }
                        }
                        .onDelete { idx in idx.forEach { context.delete(active[$0]) }; changed() }
                    }
                }
                if !done.isEmpty {
                    Section("נקנו") {
                        ForEach(done) { item in
                            Text(item.title).strikethrough().foregroundStyle(.secondary)
                                .swipeActions(edge: .leading) {
                                    Button { item.done = false; changed() } label: {
                                        Label("החזר", systemImage: "arrow.uturn.backward")
                                    }
                                }
                        }
                        .onDelete { idx in idx.forEach { context.delete(done[$0]) } }
                    }
                }
            }
            .navigationTitle("הרשימה שלי")
            .navigationDestination(for: Brand.self) { BrandDetailView(brand: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { AddWishView(prefill: nil) }
        }
    }

    private func row(_ item: WishItem) -> some View {
        let matches = CatalogStore.shared.matches(for: item)
        return VStack(alignment: .leading, spacing: 4) {
            Text(item.title).font(.body.weight(.semibold))
            if matches.isEmpty {
                Text("לא נמצאה חנות מתאימה - בחר/י חנות ידנית")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Text(matches.prefix(3).map(\.name).joined(separator: " · ")
                     + (matches.count > 3 ? " +\(matches.count - 3)" : ""))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func changed() { LocationAlerts.shared.invalidate() }
}

struct AddWishView: View {
    let prefill: Brand?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var note = ""
    @State private var stores: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("מה בא לך לקנות? למשל: נעלי ריצה", text: $title)
                    TextField("הערה (מידה, צבע…)", text: $note)
                }
                Section {
                    StorePicker(query: title, selected: $stores)
                } header: {
                    Text("איפה")
                } footer: {
                    Text(stores.isEmpty
                         ? "לא נבחרה חנות - נתאים חנויות אוטומטית לפי מה שכתבת."
                         : "תקבל/י התראה כשתהיה/י ליד החנויות שנבחרו.")
                }
            }
            .navigationTitle("מוצר חדש")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמור") {
                        context.insert(WishItem(title: title.trimmingCharacters(in: .whitespaces),
                                                note: note, brandKeys: stores))
                        LocationAlerts.shared.invalidate()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { if let prefill, stores.isEmpty { stores = [prefill.key] } }
        }
    }
}

struct WishDetailView: View {
    @Bindable var item: WishItem

    var body: some View {
        Form {
            Section {
                TextField("מוצר", text: $item.title)
                TextField("הערה", text: $item.note)
                Toggle("נקנה", isOn: $item.done)
            }
            Section {
                StorePicker(query: item.title, selected: $item.brandKeys)
            } header: {
                Text("חנויות")
            } footer: {
                Text(item.brandKeys.isEmpty
                     ? "אוטומטי: \(CatalogStore.shared.matches(for: item).map(\.name).joined(separator: ", "))"
                     : "סמן/י או בטל/י חנויות. בלי בחירה - התאמה אוטומטית.")
            }
            let matches = CatalogStore.shared.matches(for: item)
            if !matches.isEmpty {
                Section("פרטי החנויות") {
                    ForEach(matches) { b in NavigationLink(value: b) { BrandRow(brand: b) } }
                }
            }
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { LocationAlerts.shared.invalidate() }
    }
}
