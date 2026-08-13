import Foundation
import SwiftData

enum AppLanguage: String, CaseIterable, Identifiable {
    case english
    case norwegian

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english: "English"
        case .norwegian: "Norsk"
        }
    }
}

enum GroceryStore: String, CaseIterable, Identifiable {
    case coopExtra
    case meny
    case rema1000

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .coopExtra: "Coop Extra"
        case .meny: "Meny"
        case .rema1000: "Rema 1000"
        }
    }
}

enum MealSlot: String, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case snack

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.breakfast, .english): "Breakfast"
        case (.breakfast, .norwegian): "Frokost"
        case (.lunch, .english): "Lunch"
        case (.lunch, .norwegian): "Lunsj"
        case (.dinner, .english): "Dinner"
        case (.dinner, .norwegian): "Middag"
        case (.snack, .english): "Snack"
        case (.snack, .norwegian): "Mellommaltid"
        }
    }
}

@Model
final class Recipe {
    var title: String
    var summary: String
    var servings: Int
    var ingredients: [String]
    var steps: [String]
    var estimatedCost: Double
    var createdAt: Date

    init(title: String, summary: String, servings: Int, ingredients: [String], steps: [String], estimatedCost: Double = 0, createdAt: Date = .now) {
        self.title = title
        self.summary = summary
        self.servings = servings
        self.ingredients = ingredients
        self.steps = steps
        self.estimatedCost = estimatedCost
        self.createdAt = createdAt
    }
}

@Model
final class MealPlanEntry {
    var date: Date
    var mealSlotRawValue: String
    var recipeTitle: String
    var servings: Int

    init(date: Date, mealSlot: MealSlot, recipeTitle: String, servings: Int) {
        self.date = date
        self.mealSlotRawValue = mealSlot.rawValue
        self.recipeTitle = recipeTitle
        self.servings = servings
    }

    var mealSlot: MealSlot {
        MealSlot(rawValue: mealSlotRawValue) ?? .dinner
    }
}

@Model
final class ShoppingListItem {
    var name: String
    var quantity: String
    var unit: String
    var isChecked: Bool
    var targetStoreRawValue: String
    var estimatedUnitPrice: Double
    var sourceRecipeTitle: String
    var createdAt: Date

    init(name: String, quantity: String, unit: String, targetStore: GroceryStore, estimatedUnitPrice: Double, sourceRecipeTitle: String = "", createdAt: Date = .now) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.isChecked = false
        self.targetStoreRawValue = targetStore.rawValue
        self.estimatedUnitPrice = estimatedUnitPrice
        self.sourceRecipeTitle = sourceRecipeTitle
        self.createdAt = createdAt
    }

    var targetStore: GroceryStore {
        GroceryStore(rawValue: targetStoreRawValue) ?? .rema1000
    }
}

@Model
final class StorePrice {
    var itemName: String
    var storeRawValue: String
    var price: Double
    var unit: String
    var currency: String
    var updatedAt: Date

    init(itemName: String, store: GroceryStore, price: Double, unit: String = "stk", currency: String = "NOK", updatedAt: Date = .now) {
        self.itemName = itemName
        self.storeRawValue = store.rawValue
        self.price = price
        self.unit = unit
        self.currency = currency
        self.updatedAt = updatedAt
    }

    var store: GroceryStore {
        GroceryStore(rawValue: storeRawValue) ?? .rema1000
    }
}

@Model
final class ReceiptLineItem {
    var itemName: String
    var price: Double
    var storeRawValue: String
    var purchasedAt: Date
    var rawText: String

    init(itemName: String, price: Double, store: GroceryStore, purchasedAt: Date = .now, rawText: String = "") {
        self.itemName = itemName
        self.price = price
        self.storeRawValue = store.rawValue
        self.purchasedAt = purchasedAt
        self.rawText = rawText
    }

    var store: GroceryStore {
        GroceryStore(rawValue: storeRawValue) ?? .rema1000
    }
}
