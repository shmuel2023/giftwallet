import SwiftUI
import CoreLocation

struct CardBadge: View {
    let cardId: String
    var body: some View {
        Text(CardStyle.shortName(cardId))
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(CardStyle.color(cardId))
            .background(CardStyle.color(cardId).opacity(0.14), in: Capsule())
    }
}

struct BrandLogo: View {
    let brand: Brand
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let s = brand.primary.logoUrl, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { placeholder }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            CardStyle.color(brand.cardIds.first ?? "").opacity(0.15)
            Text(String(brand.name.prefix(1)))
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(CardStyle.color(brand.cardIds.first ?? ""))
        }
    }
}

struct BrandRow: View {
    let brand: Brand
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            BrandLogo(brand: brand)
            VStack(alignment: .leading, spacing: 3) {
                Text(brand.name).font(.body.weight(.semibold)).lineLimit(1)
                if let s = detail ?? brand.subtitle {
                    Text(s).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 4) {
                    ForEach(brand.cardIds, id: \.self) { CardBadge(cardId: $0) }
                    if brand.onlineRedeem {
                        Image(systemName: "globe").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Pick businesses for a wish-list item or a store-specific voucher.
struct StorePicker: View {
    let query: String
    @Binding var selected: [String]
    var limit = 8

    var body: some View {
        let catalog = CatalogStore.shared
        let pinned = selected.compactMap { catalog.brand($0) }
        let suggestions = query.trimmingCharacters(in: .whitespaces).isEmpty ? [] :
            catalog.search(query).filter { !selected.contains($0.key) }.prefix(limit)
        ForEach(pinned) { b in row(b, on: true) }
        ForEach(Array(suggestions)) { b in row(b, on: false) }
        if pinned.isEmpty && suggestions.isEmpty {
            Text("הקלד/י מוצר, מותג או חנות כדי לראות הצעות")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func row(_ b: Brand, on: Bool) -> some View {
        Button {
            if on { selected.removeAll { $0 == b.key } } else { selected.append(b.key) }
        } label: {
            HStack {
                BrandRow(brand: b)
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Color.accentColor : .secondary)
                    .font(.title3)
            }
        }
        .buttonStyle(.plain)
    }
}

/// One-shot current location with a timeout.
enum CurrentLocation {
    static func get(timeout: TimeInterval = 10) async -> CLLocation? {
        await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if let loc = update.location { return loc }
                    }
                } catch {}
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

extension Date {
    var shortHebrew: String {
        formatted(.dateTime.day().month(.twoDigits).year().locale(Locale(identifier: "he_IL")))
    }
}
