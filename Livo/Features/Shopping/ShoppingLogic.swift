import Foundation
import SwiftData

struct ItemGroup: Identifiable {
    let category: String
    let items: [ShoppingItem]
    var id: String { category }
}

struct ShoppingEstimate {
    var cents: Int64 = 0
    /// Items without a price, left out of `cents`.
    var missing = 0
}

enum ShoppingLogic {
    static let categories = ["Hortifruti", "Açougue", "Padaria", "Laticínios", "Mercearia", "Bebidas",
                             "Limpeza", "Higiene", "Casa", "Eletrônicos", "Vestuário", "Outros"]

    /// Unit price × quantity, rounded to the cent.
    static func lineTotal(_ i: ShoppingItem) -> Int64? {
        guard let p = i.priceCents else { return nil }
        return Int64((Double(p) * i.quantity).rounded())
    }

    static func estimate(_ items: [ShoppingItem]) -> ShoppingEstimate {
        items.reduce(into: ShoppingEstimate()) { e, i in
            if let line = lineTotal(i) { e.cents += line } else { e.missing += 1 }
        }
    }

    /// Categories alphabetically, uncategorized last; items by name.
    static func groups(_ items: [ShoppingItem]) -> [ItemGroup] {
        Dictionary(grouping: items, by: \.category)
            .map { ItemGroup(category: $0.key, items: $0.value.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }) }
            .sorted { a, b in
                if a.category.isEmpty != b.category.isEmpty { return !a.category.isEmpty }
                return a.category.localizedCompare(b.category) == .orderedAscending
            }
    }
}

@MainActor
enum ShoppingStore {
    /// Records a PricePoint only when the price actually changes, so the history shows real observations.
    static func setPrice(_ cents: Int64?, store: String, for item: ShoppingItem, at date: Date = .now, in ctx: ModelContext) {
        item.store = store
        guard let cents else {
            item.priceCents = nil
            return
        }
        if cents != item.priceCents {
            let p = PricePoint(priceCents: cents, store: store, observedAt: date)
            ctx.insert(p)
            p.item = item
        }
        item.priceCents = cents
    }

    static func toggleBought(_ item: ShoppingItem) {
        item.bought.toggle()
        item.boughtAt = item.bought ? .now : nil
    }

    static func clearBought(_ list: ShoppingList, in ctx: ModelContext) {
        for i in (list.items ?? []) where i.bought {
            list.items?.removeAll { $0 == i }
            ctx.delete(i)
        }
    }
}
