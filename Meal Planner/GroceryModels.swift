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

enum AppCurrency: String, CaseIterable, Identifiable {
    case nok = "NOK"
    case sek = "SEK"
    case dkk = "DKK"
    case eur = "EUR"
    case usd = "USD"
    case gbp = "GBP"
    case isk = "ISK"
    case chf = "CHF"
    case cad = "CAD"
    case aud = "AUD"

    var id: String { rawValue }

    var title: String { rawValue }
}

enum DietaryPreference: String, CaseIterable, Identifiable {
    case vegetarian
    case vegan
    case pescatarian
    case glutenFree
    case dairyFree
    case nutFree
    case lowCarb
    case highProtein

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.vegetarian, .english): "Vegetarian"
        case (.vegetarian, .norwegian): "Vegetar"
        case (.vegan, .english): "Vegan"
        case (.vegan, .norwegian): "Vegansk"
        case (.pescatarian, .english): "Pescatarian"
        case (.pescatarian, .norwegian): "Pescetar"
        case (.glutenFree, .english): "Gluten-free"
        case (.glutenFree, .norwegian): "Glutenfri"
        case (.dairyFree, .english): "Dairy-free"
        case (.dairyFree, .norwegian): "Melkefri"
        case (.nutFree, .english): "Nut-free"
        case (.nutFree, .norwegian): "Nøttefri"
        case (.lowCarb, .english): "Low carb"
        case (.lowCarb, .norwegian): "Lavkarbo"
        case (.highProtein, .english): "High protein"
        case (.highProtein, .norwegian): "Proteinrik"
        }
    }
}

enum ReceiptRecognitionLanguage: String, CaseIterable, Identifiable {
    case norwegianAndEnglish
    case norwegian
    case english

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.norwegianAndEnglish, .english): "Norwegian + English"
        case (.norwegianAndEnglish, .norwegian): "Norsk + engelsk"
        case (.norwegian, .english): "Norwegian"
        case (.norwegian, .norwegian): "Norsk"
        case (.english, .english): "English"
        case (.english, .norwegian): "Engelsk"
        }
    }
}

enum GroceryStore: String, CaseIterable, Identifiable {
    case sevenEleven
    case bunnpris
    case ccMat
    case coopMarked
    case coopMega
    case coopObs
    case coopPrix
    case deliDeLuca
    case europris
    case euroSpar
    case coopExtra
    case jacobs
    case joker
    case kaffebrenneriet
    case kiwi
    case matkroken
    case meny
    case mix
    case narvesen
    case naerbutikken
    case rema1000
    case spar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sevenEleven: "7-Eleven"
        case .bunnpris: "Bunnpris"
        case .ccMat: "CC Mat"
        case .coopMarked: "Coop Marked"
        case .coopMega: "Coop Mega"
        case .coopObs: "Coop Obs!"
        case .coopPrix: "Coop Prix"
        case .deliDeLuca: "Deli de Luca"
        case .europris: "Europris"
        case .euroSpar: "EuroSpar"
        case .coopExtra: "Extra"
        case .jacobs: "Jacob's"
        case .joker: "Joker"
        case .kaffebrenneriet: "Kaffebrenneriet"
        case .kiwi: "Kiwi"
        case .matkroken: "Matkroken"
        case .meny: "Meny"
        case .mix: "MIX"
        case .narvesen: "Narvesen"
        case .naerbutikken: "Nærbutikken"
        case .rema1000: "REMA 1000"
        case .spar: "SPAR"
        }
    }

    var storeType: String {
        switch self {
        case .sevenEleven, .coopMarked, .deliDeLuca, .joker, .kaffebrenneriet, .matkroken, .mix, .narvesen, .naerbutikken:
            "Convenience"
        case .bunnpris, .coopPrix, .kiwi, .rema1000:
            "Discount"
        case .ccMat, .coopMega, .euroSpar, .coopExtra, .jacobs, .meny, .spar:
            "Supermarket"
        case .coopObs:
            "Hypermarket"
        case .europris:
            "Department store"
        }
    }

    var parentCompany: String {
        switch self {
        case .sevenEleven, .narvesen, .rema1000:
            "Reitan Group"
        case .bunnpris:
            "I. K. Lykke"
        case .ccMat:
            "CC Mat"
        case .coopMarked, .coopMega, .coopObs, .coopPrix, .coopExtra, .matkroken:
            "Coop Norge"
        case .deliDeLuca, .euroSpar, .jacobs, .joker, .kaffebrenneriet, .kiwi, .meny, .mix, .naerbutikken, .spar:
            "NorgesGruppen"
        case .europris:
            "Nordic Capital Fund VII"
        }
    }

    static var defaultTrackedStores: [GroceryStore] {
        [.coopExtra, .meny, .rema1000]
    }
}

@Model
final class UserSettings {
    var displayName: String
    var email: String
    var preferredLanguageRawValue: String
    var enabledStoreRawValues: [String]
    var weeklyBudget: Double
    var currencyCode: String
    var receiptRemindersEnabled: Bool
    var shoppingRemindersEnabled: Bool
    var householdSize: Int = 2
    var planningHorizonDays: Int = 7
    var weekStartsOnMonday: Bool = true
    var autoAddIngredientsToShoppingList: Bool = true
    var preferCheapestTrackedStore: Bool = true
    var showBudgetWarnings: Bool = true
    var includeTaxInPrices: Bool = true
    var receiptRecognitionLanguageRawValue: String = ReceiptRecognitionLanguage.norwegianAndEnglish.rawValue
    var dietaryPreferenceRawValues: [String] = []

    init(
        displayName: String = "",
        email: String = "",
        preferredLanguage: AppLanguage = .english,
        enabledStores: [GroceryStore] = GroceryStore.defaultTrackedStores,
        weeklyBudget: Double = 0,
        currencyCode: String = AppCurrency.nok.rawValue,
        receiptRemindersEnabled: Bool = false,
        shoppingRemindersEnabled: Bool = false,
        householdSize: Int = 2,
        planningHorizonDays: Int = 7,
        weekStartsOnMonday: Bool = true,
        autoAddIngredientsToShoppingList: Bool = true,
        preferCheapestTrackedStore: Bool = true,
        showBudgetWarnings: Bool = true,
        includeTaxInPrices: Bool = true,
        receiptRecognitionLanguage: ReceiptRecognitionLanguage = .norwegianAndEnglish,
        dietaryPreferences: [DietaryPreference] = []
    ) {
        self.displayName = displayName
        self.email = email
        self.preferredLanguageRawValue = preferredLanguage.rawValue
        self.enabledStoreRawValues = enabledStores.map(\.rawValue)
        self.weeklyBudget = weeklyBudget
        self.currencyCode = currencyCode
        self.receiptRemindersEnabled = receiptRemindersEnabled
        self.shoppingRemindersEnabled = shoppingRemindersEnabled
        self.householdSize = householdSize
        self.planningHorizonDays = planningHorizonDays
        self.weekStartsOnMonday = weekStartsOnMonday
        self.autoAddIngredientsToShoppingList = autoAddIngredientsToShoppingList
        self.preferCheapestTrackedStore = preferCheapestTrackedStore
        self.showBudgetWarnings = showBudgetWarnings
        self.includeTaxInPrices = includeTaxInPrices
        self.receiptRecognitionLanguageRawValue = receiptRecognitionLanguage.rawValue
        self.dietaryPreferenceRawValues = dietaryPreferences.map(\.rawValue)
    }

    var preferredLanguage: AppLanguage {
        get { AppLanguage(rawValue: preferredLanguageRawValue) ?? .english }
        set { preferredLanguageRawValue = newValue.rawValue }
    }

    var currency: AppCurrency {
        get { AppCurrency(rawValue: currencyCode) ?? .nok }
        set { currencyCode = newValue.rawValue }
    }

    var receiptRecognitionLanguage: ReceiptRecognitionLanguage {
        get { ReceiptRecognitionLanguage(rawValue: receiptRecognitionLanguageRawValue) ?? .norwegianAndEnglish }
        set { receiptRecognitionLanguageRawValue = newValue.rawValue }
    }

    var dietaryPreferences: [DietaryPreference] {
        DietaryPreference.allCases.filter { dietaryPreferenceRawValues.contains($0.rawValue) }
    }

    var enabledStores: [GroceryStore] {
        GroceryStore.allCases.filter { enabledStoreRawValues.contains($0.rawValue) }
    }

    func isStoreEnabled(_ store: GroceryStore) -> Bool {
        enabledStoreRawValues.contains(store.rawValue)
    }

    func setStore(_ store: GroceryStore, isEnabled: Bool) {
        var values = enabledStoreRawValues
        if isEnabled {
            if !values.contains(store.rawValue) {
                values.append(store.rawValue)
            }
        } else {
            values.removeAll { $0 == store.rawValue }
        }
        enabledStoreRawValues = values
    }

    func hasDietaryPreference(_ preference: DietaryPreference) -> Bool {
        dietaryPreferenceRawValues.contains(preference.rawValue)
    }

    func setDietaryPreference(_ preference: DietaryPreference, isEnabled: Bool) {
        var values = dietaryPreferenceRawValues
        if isEnabled {
            if !values.contains(preference.rawValue) {
                values.append(preference.rawValue)
            }
        } else {
            values.removeAll { $0 == preference.rawValue }
        }
        dietaryPreferenceRawValues = values
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

enum ShoppingCategory: String, CaseIterable, Identifiable {
    case produce
    case meatSeafood
    case dairy
    case bakery
    case pantry
    case frozen
    case household
    case personalCare
    case other

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.produce, .english): "Produce"
        case (.produce, .norwegian): "Frukt og grønt"
        case (.meatSeafood, .english): "Meat & seafood"
        case (.meatSeafood, .norwegian): "Kjøtt og fisk"
        case (.dairy, .english): "Dairy"
        case (.dairy, .norwegian): "Meieri"
        case (.bakery, .english): "Bakery"
        case (.bakery, .norwegian): "Bakervarer"
        case (.pantry, .english): "Pantry"
        case (.pantry, .norwegian): "Tørrvarer"
        case (.frozen, .english): "Frozen"
        case (.frozen, .norwegian): "Frysevarer"
        case (.household, .english): "Household"
        case (.household, .norwegian): "Husholdning"
        case (.personalCare, .english): "Personal care"
        case (.personalCare, .norwegian): "Personlig pleie"
        case (.other, .english): "Other"
        case (.other, .norwegian): "Annet"
        }
    }
}

enum ShoppingPriority: String, CaseIterable, Identifiable {
    case low
    case normal
    case high

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.low, .english): "Low"
        case (.low, .norwegian): "Lav"
        case (.normal, .english): "Normal"
        case (.normal, .norwegian): "Normal"
        case (.high, .english): "High"
        case (.high, .norwegian): "Høy"
        }
    }
}

enum RecipeCourse: String, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case dessert
    case snack
    case side

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.breakfast, .english): "Breakfast"
        case (.breakfast, .norwegian): "Frokost"
        case (.lunch, .english): "Lunch"
        case (.lunch, .norwegian): "Lunsj"
        case (.dinner, .english): "Dinner"
        case (.dinner, .norwegian): "Middag"
        case (.dessert, .english): "Dessert"
        case (.dessert, .norwegian): "Dessert"
        case (.snack, .english): "Snack"
        case (.snack, .norwegian): "Mellommaltid"
        case (.side, .english): "Side"
        case (.side, .norwegian): "Tilbehør"
        }
    }
}

enum RecipeDifficulty: String, CaseIterable, Identifiable {
    case easy
    case medium
    case hard

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.easy, .english): "Easy"
        case (.easy, .norwegian): "Enkel"
        case (.medium, .english): "Medium"
        case (.medium, .norwegian): "Middels"
        case (.hard, .english): "Hard"
        case (.hard, .norwegian): "Vanskelig"
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
    var courseRawValue: String = RecipeCourse.dinner.rawValue
    var difficultyRawValue: String = RecipeDifficulty.easy.rawValue
    var cuisine: String = ""
    var tags: [String] = []
    var prepMinutes: Int = 10
    var cookMinutes: Int = 20
    var caloriesPerServing: Int = 0
    var proteinGrams: Double = 0
    var carbohydrateGrams: Double = 0
    var fatGrams: Double = 0
    var fiberGrams: Double = 0
    var isFavorite: Bool = false
    var sourceName: String = ""
    var sourceURL: String = ""
    var notes: String = ""
    var lastCookedAt: Date?
    var timesCooked: Int = 0
    var createdAt: Date

    init(
        title: String,
        summary: String,
        servings: Int,
        ingredients: [String],
        steps: [String],
        estimatedCost: Double = 0,
        course: RecipeCourse = .dinner,
        difficulty: RecipeDifficulty = .easy,
        cuisine: String = "",
        tags: [String] = [],
        prepMinutes: Int = 10,
        cookMinutes: Int = 20,
        caloriesPerServing: Int = 0,
        proteinGrams: Double = 0,
        carbohydrateGrams: Double = 0,
        fatGrams: Double = 0,
        fiberGrams: Double = 0,
        sourceName: String = "",
        sourceURL: String = "",
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.title = title
        self.summary = summary
        self.servings = servings
        self.ingredients = ingredients
        self.steps = steps
        self.estimatedCost = estimatedCost
        self.courseRawValue = course.rawValue
        self.difficultyRawValue = difficulty.rawValue
        self.cuisine = cuisine
        self.tags = tags
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.caloriesPerServing = caloriesPerServing
        self.proteinGrams = proteinGrams
        self.carbohydrateGrams = carbohydrateGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.notes = notes
        self.createdAt = createdAt
    }

    var course: RecipeCourse {
        get { RecipeCourse(rawValue: courseRawValue) ?? .dinner }
        set { courseRawValue = newValue.rawValue }
    }

    var difficulty: RecipeDifficulty {
        get { RecipeDifficulty(rawValue: difficultyRawValue) ?? .easy }
        set { difficultyRawValue = newValue.rawValue }
    }

    var totalMinutes: Int {
        prepMinutes + cookMinutes
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
    var categoryRawValue: String = ShoppingCategory.other.rawValue
    var priorityRawValue: String = ShoppingPriority.normal.rawValue
    var notes: String = ""
    var neededBy: Date?
    var createdAt: Date

    init(
        name: String,
        quantity: String,
        unit: String,
        targetStore: GroceryStore,
        estimatedUnitPrice: Double,
        sourceRecipeTitle: String = "",
        category: ShoppingCategory = .other,
        priority: ShoppingPriority = .normal,
        notes: String = "",
        neededBy: Date? = nil,
        createdAt: Date = .now
    ) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.isChecked = false
        self.targetStoreRawValue = targetStore.rawValue
        self.estimatedUnitPrice = estimatedUnitPrice
        self.sourceRecipeTitle = sourceRecipeTitle
        self.categoryRawValue = category.rawValue
        self.priorityRawValue = priority.rawValue
        self.notes = notes
        self.neededBy = neededBy
        self.createdAt = createdAt
    }

    var targetStore: GroceryStore {
        GroceryStore(rawValue: targetStoreRawValue) ?? .rema1000
    }

    var category: ShoppingCategory {
        get { ShoppingCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }

    var priority: ShoppingPriority {
        get { ShoppingPriority(rawValue: priorityRawValue) ?? .normal }
        set { priorityRawValue = newValue.rawValue }
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
