import Foundation
import SwiftData

@Model
final class ShoppingList {
    var name: String = ""
    var icon: String = "cart"
    var isWishlist: Bool = false
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \ShoppingItem.list)
    var items: [ShoppingItem]? = []

    init(name: String, isWishlist: Bool) {
        self.name = name
        self.isWishlist = isWishlist
        self.icon = isWishlist ? "star" : "cart"
    }
}

@Model
final class ShoppingItem {
    var name: String = ""
    var quantity: Double = 1
    var unit: String = ""
    var category: String = ""
    /// Unit price typed by the user. Never fetched; see `prices` for when it was observed.
    var priceCents: Int64?
    var store: String = ""
    var link: String = ""
    var note: String = ""
    var bought: Bool = false
    var boughtAt: Date?
    var priorityRaw: Int = Priority.media.rawValue
    var createdAt: Date = Date()
    var list: ShoppingList?
    @Relationship(deleteRule: .cascade, inverse: \PricePoint.item)
    var prices: [PricePoint]? = []

    init(name: String) { self.name = name }

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .media }
        set { priorityRaw = newValue.rawValue }
    }
}

/// One observed price. `sourceRaw` is "manual" today; price APIs, when added, must record their own source.
@Model
final class PricePoint {
    var priceCents: Int64 = 0
    var store: String = ""
    var observedAt: Date = Date()
    var sourceRaw: String = "manual"
    var item: ShoppingItem?

    init(priceCents: Int64, store: String, observedAt: Date) {
        self.priceCents = priceCents
        self.store = store
        self.observedAt = observedAt
    }
}
