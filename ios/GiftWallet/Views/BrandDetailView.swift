import SwiftUI
import SwiftData
import MapKit

struct BrandDetailView: View {
    let brand: Brand

    @Query(filter: #Predicate<Voucher> { !$0.archived }) private var vouchers: [Voucher]
    @State private var branches: [Branch] = []
    @State private var searching = false
    @State private var searched = false
    @State private var showAddWish = false
    @State private var showAddVoucher = false

    var body: some View {
        let catalog = CatalogStore.shared
        let usable = vouchers.filter { $0.isUsable && $0.accepts(brand) }

        List {
            Section {
                HStack(spacing: 14) {
                    BrandLogo(brand: brand, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(brand.name).font(.title2.bold())
                        if let s = brand.subtitle { Text(s).foregroundStyle(.secondary) }
                        HStack(spacing: 4) { ForEach(brand.cardIds, id: \.self) { CardBadge(cardId: $0) } }
                    }
                }
                if brand.onlineRedeem {
                    Label("אפשר לממש גם באתר", systemImage: "globe").font(.subheadline)
                }
            }

            if !usable.isEmpty {
                Section("השוברים שלך שמתאימים כאן") {
                    ForEach(usable) { v in
                        HStack {
                            Text(v.displayTitle)
                            Spacer()
                            Text(v.balance.shekels).bold()
                        }
                    }
                }
            }

            Section("איפה") {
                if let c = brand.coordinate {
                    Map(initialPosition: .region(MKCoordinateRegion(center: c, latitudinalMeters: 800,
                                                                    longitudinalMeters: 800))) {
                        Marker(brand.name, coordinate: c)
                    }
                    .frame(height: 170)
                    .listRowInsets(EdgeInsets())
                }
                if let address = brand.primary.address {
                    Button {
                        if let c = brand.coordinate {
                            Branch(id: brand.key, brandKey: brand.key, name: brand.name, address: address,
                                   coordinate: c, distance: 0).openInMaps()
                        } else if let q = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                                  let url = URL(string: "maps://?q=\(q)") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label(address, systemImage: "arrow.triangle.turn.up.right.diamond")
                    }
                }
                if brand.isChain {
                    if branches.isEmpty {
                        Button {
                            Task { await findBranches() }
                        } label: {
                            HStack {
                                Label(searched ? "לא נמצא סניף ב-5 ק״מ" : "מצא סניף קרוב",
                                      systemImage: "location.magnifyingglass")
                                if searching { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(searching)
                    }
                    ForEach(branches) { b in
                        Button { b.openInMaps() } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(b.name)
                                    if let a = b.address { Text(a).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Text(b.distanceText).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let s = brand.primary.branchLocatorUrl, let url = URL(string: s) {
                    Link(destination: url) { Label("כל הסניפים באתר", systemImage: "list.bullet") }
                }
            }

            let p = brand.primary
            if p.phone != nil || p.website != nil || p.reservationUrl != nil {
                Section("יצירת קשר") {
                    if let phone = p.phone,
                       let url = URL(string: "tel:" + phone.filter { "0123456789*#+".contains($0) }) {
                        Link(destination: url) { Label(phone, systemImage: "phone") }
                    }
                    if let s = p.website, let url = URL(string: s) {
                        Link(destination: url) { Label("אתר", systemImage: "safari") }
                    }
                    if let s = p.reservationUrl, let url = URL(string: s) {
                        Link(destination: url) { Label("הזמנת מקום", systemImage: "calendar") }
                    }
                }
            }

            ForEach(brand.entries) { e in
                let cardTerms = catalog.cards.first { $0.id == e.card }?.terms ?? ""
                let text = [e.terms, cardTerms].filter { !$0.isEmpty }.joined(separator: "\n\n")
                if !text.isEmpty {
                    Section("תנאי מימוש · \(CardStyle.shortName(e.card))") {
                        Text(text).font(.subheadline)
                    }
                }
            }

            Section {
                Button { showAddWish = true } label: {
                    Label("הוסף מוצר לרשימה מהחנות הזו", systemImage: "cart.badge.plus")
                }
                Button { showAddVoucher = true } label: {
                    Label("יש לי שובר לעסק הזה", systemImage: "wallet.pass")
                }
            }
        }
        .navigationTitle(brand.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddWish) { AddWishView(prefill: brand) }
        .sheet(isPresented: $showAddVoucher) { VoucherEditView(voucher: nil, prefillBrand: brand) }
    }

    private func findBranches() async {
        searching = true
        defer { searching = false; searched = true }
        guard let loc = await CurrentLocation.get() else { return }
        branches = await BranchFinder.branches(of: brand, near: loc, radius: 5000, limit: 5)
    }
}
