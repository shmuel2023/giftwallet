import SwiftUI
import SwiftData

struct VouchersView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Voucher.createdAt, order: .reverse) private var all: [Voucher]
    @State private var editing: Voucher?
    @State private var showAdd = false

    var body: some View {
        let active = all.filter { !$0.archived }
            .sorted { ($0.expiry ?? .distantFuture) < ($1.expiry ?? .distantFuture) }
        let archived = all.filter(\.archived)
        let totals = Dictionary(grouping: active.filter(\.isUsable), by: \.cardId)
            .mapValues { $0.reduce(0) { $0 + $1.balance } }

        NavigationStack {
            List {
                if all.isEmpty {
                    ContentUnavailableView {
                        Label("אין שוברים עדיין", systemImage: "wallet.pass")
                    } description: {
                        Text("הוסף/י שובר כדי לראות יתרה, לקבל תזכורת לפני שהוא פג, ולשמוע כשאת/ה ליד מקום שמכבד אותו.")
                    } actions: {
                        Button("הוסף שובר") { showAdd = true }.buttonStyle(.borderedProminent)
                    }
                }

                if !totals.isEmpty {
                    Section {
                        ForEach(totals.sorted { $0.key < $1.key }, id: \.key) { card, total in
                            NavigationLink {
                                SearchView(cardFilter: card == "other" ? nil : card, embedded: true)
                            } label: {
                                HStack {
                                    CardBadge(cardId: card)
                                    Spacer()
                                    Text(total.shekels).font(.title3.bold())
                                }
                            }
                            .disabled(card == "other")
                        }
                    } header: {
                        Text("יתרה לפי כרטיס")
                    } footer: {
                        Text("הקש/י על כרטיס לראות איפה אפשר לממש אותו")
                    }
                }

                if !active.isEmpty {
                    Section("השוברים שלי") {
                        ForEach(active) { v in
                            Button { editing = v } label: { VoucherRow(voucher: v) }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .leading) {
                                    Button { v.archived = true; changed() } label: {
                                        Label("מומש", systemImage: "checkmark")
                                    }.tint(.green)
                                }
                        }
                        .onDelete { idx in idx.forEach { context.delete(active[$0]) }; changed() }
                    }
                }

                if !archived.isEmpty {
                    Section("מומשו") {
                        ForEach(archived) { v in
                            VoucherRow(voucher: v).opacity(0.5)
                                .swipeActions(edge: .leading) {
                                    Button { v.archived = false; changed() } label: {
                                        Label("החזר", systemImage: "arrow.uturn.backward")
                                    }
                                }
                        }
                        .onDelete { idx in idx.forEach { context.delete(archived[$0]) }; changed() }
                    }
                }
            }
            .navigationTitle("השוברים שלי")
            .navigationDestination(for: Brand.self) { BrandDetailView(brand: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { VoucherEditView(voucher: nil, prefillBrand: nil) }
            .sheet(item: $editing) { VoucherEditView(voucher: $0, prefillBrand: nil) }
        }
    }

    private func changed() {
        LocationAlerts.shared.invalidate()
        Task { await Reminders.reschedule(container: context.container) }
    }
}

struct VoucherRow: View {
    let voucher: Voucher

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(CardStyle.color(voucher.cardId))
                .frame(width: 6, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(voucher.displayTitle).font(.body.weight(.semibold))
                if let brandKey = voucher.brandKey, let b = CatalogStore.shared.brand(brandKey) {
                    Text("רק ב-\(b.name)").font(.caption).foregroundStyle(.secondary)
                }
                expiryText
            }
            Spacer()
            Text(voucher.balance.shekels).font(.title3.bold())
        }
        .contentShape(Rectangle())
        .contextMenu {
            if !voucher.code.isEmpty {
                Button { UIPasteboard.general.string = voucher.code } label: {
                    Label("העתק קוד", systemImage: "doc.on.doc")
                }
            }
        }
    }

    @ViewBuilder private var expiryText: some View {
        if let expiry = voucher.expiry, let days = voucher.daysLeft {
            let urgent = days <= 30
            Text(days < 0 ? "פג תוקף" : "בתוקף עד \(expiry.shortHebrew)" + (urgent ? " · עוד \(days) ימים" : ""))
                .font(.caption)
                .foregroundStyle(days < 0 ? .red : urgent ? .orange : .secondary)
        }
    }
}

struct VoucherEditView: View {
    let voucher: Voucher?
    let prefillBrand: Brand?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var cardId = ""
    @State private var title = ""
    @State private var balanceText = ""
    @State private var hasExpiry = true
    @State private var expiry = Calendar.current.date(byAdding: .year, value: 5, to: .now)!
    @State private var code = ""
    @State private var note = ""
    @State private var stores: [String] = []
    @State private var storeQuery = ""

    var body: some View {
        let myCards = AppSettings.shared.selectedCards.sorted() + ["other"]
        NavigationStack {
            Form {
                Section {
                    Picker("כרטיס", selection: $cardId) {
                        ForEach(myCards, id: \.self) { Text(CardStyle.shortName($0)).tag($0) }
                    }
                    TextField("שם (למשל: מתנה מהעבודה)", text: $title)
                    HStack {
                        Text("יתרה ₪")
                        TextField("0", text: $balanceText).keyboardType(.decimalPad)
                    }
                }
                Section {
                    Toggle("יש תאריך תפוגה", isOn: $hasExpiry)
                    if hasExpiry {
                        DatePicker("בתוקף עד", selection: $expiry, displayedComponents: .date)
                    }
                } footer: {
                    Text("נזכיר לך 30 יום, שבוע ויום לפני שהשובר פג.")
                }
                Section {
                    TextField("קוד השובר", text: $code)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("הערה", text: $note)
                }
                Section {
                    if stores.isEmpty {
                        TextField("חפש עסק", text: $storeQuery)
                    }
                    StorePicker(query: storeQuery, selected: $stores, limit: 5)
                } header: {
                    Text("שובר לעסק מסוים? (לא חובה)")
                } footer: {
                    Text("השאר/י ריק אם זה שובר כללי לכל העסקים של הכרטיס.")
                }
                if let voucher {
                    Section {
                        Button(voucher.archived ? "החזר לשוברים פעילים" : "סמן כמומש") {
                            voucher.archived.toggle()
                            finish()
                        }
                        Button("מחק שובר", role: .destructive) {
                            context.delete(voucher)
                            finish()
                        }
                    }
                }
            }
            .navigationTitle(voucher == nil ? "שובר חדש" : "עריכת שובר")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("שמור") { save() } }
            }
            .onAppear(perform: load)
            .onChange(of: stores) { _, new in if new.count > 1 { stores = [new.last!] } }
        }
    }

    private func load() {
        if let v = voucher {
            cardId = v.cardId; title = v.title; code = v.code; note = v.note
            balanceText = v.balance > 0 ? String(format: v.balance.rounded() == v.balance ? "%.0f" : "%.2f", v.balance) : ""
            hasExpiry = v.expiry != nil
            if let e = v.expiry { expiry = e }
            stores = v.brandKey.map { [$0] } ?? []
        } else {
            cardId = prefillBrand?.cardIds.first ?? AppSettings.shared.selectedCards.sorted().first ?? "other"
            if let b = prefillBrand { stores = [b.key]; title = b.name }
        }
    }

    private func save() {
        let balance = Double(balanceText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let v = voucher ?? Voucher(cardId: cardId)
        v.cardId = cardId
        v.title = title.trimmingCharacters(in: .whitespaces)
        v.balance = balance
        v.expiry = hasExpiry ? expiry : nil
        v.code = code.trimmingCharacters(in: .whitespaces)
        v.note = note
        v.brandKey = stores.first
        if voucher == nil { context.insert(v) }
        finish()
    }

    private func finish() {
        try? context.save()
        LocationAlerts.shared.invalidate()
        let container = context.container
        Task { await Reminders.reschedule(container: container) }
        dismiss()
    }
}
