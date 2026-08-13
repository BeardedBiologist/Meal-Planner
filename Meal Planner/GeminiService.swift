import Foundation
import SwiftData
import Observation

struct ChatMessage: Identifiable {
    enum Role { case user, assistant }
    let id: UUID
    let role: Role
    let text: String
    let timestamp: Date
    var toolActions: [String]

    init(id: UUID = UUID(), role: Role, text: String, timestamp: Date = .now, toolActions: [String] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.toolActions = toolActions
    }
}

@MainActor
@Observable
final class GeminiService {
    static let shared = GeminiService()

    private(set) var messages: [ChatMessage] = []
    private(set) var isLoading = false
    private(set) var lastError: String?
    private(set) var activeConversationID: UUID?

    private var apiKey: String {
        ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""
    }
    private let modelIDs = [
        "gemini-3.6-flash",
        "gemini-3.5-flash",
        "gemini-3.1-flash-lite"
    ]
    private var history: [[String: Any]] = []

    private var modelContext: ModelContext?
    var recipes: [Recipe] = []
    var mealPlans: [MealPlanEntry] = []
    var shoppingItems: [ShoppingListItem] = []
    var storePrices: [StorePrice] = []
    var settings: UserSettings?

    func configure(context: ModelContext, recipes: [Recipe], mealPlans: [MealPlanEntry], shoppingItems: [ShoppingListItem], storePrices: [StorePrice], settings: UserSettings?) {
        self.modelContext = context
        self.recipes = recipes
        self.mealPlans = mealPlans
        self.shoppingItems = shoppingItems
        self.storePrices = storePrices
        self.settings = settings
        loadMostRecentConversationIfNeeded(context: context)
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isLoading else { return }

        let userMessage = ChatMessage(role: .user, text: trimmed)
        messages.append(userMessage)
        persist(userMessage)
        history.append(["role": "user", "parts": [["text": trimmed]]])
        isLoading = true
        lastError = nil

        do {
            let (reply, actions) = try await runTurn()
            history.append(["role": "model", "parts": [["text": reply]]])
            let assistantMessage = ChatMessage(role: .assistant, text: reply, toolActions: actions)
            messages.append(assistantMessage)
            persist(assistantMessage)
        } catch {
            lastError = error.localizedDescription
        }

        isLoading = false
    }

    func startNewConversation() {
        guard let modelContext else { return }
        let conversation = ChatConversation()
        modelContext.insert(conversation)
        activeConversationID = conversation.id
        messages = []
        history = []
        lastError = nil
    }

    func loadConversation(_ conversation: ChatConversation) {
        activeConversationID = conversation.id
        lastError = nil
        let entries = fetchEntries(for: conversation.id)
        messages = entries.map { entry in
            ChatMessage(
                id: entry.id,
                role: entry.roleRawValue == "user" ? .user : .assistant,
                text: entry.text,
                timestamp: entry.timestamp,
                toolActions: entry.toolActions
            )
        }
        history = messages.map { message in
            [
                "role": message.role == .user ? "user" : "model",
                "parts": [["text": message.text]]
            ]
        }
    }

    private func loadMostRecentConversationIfNeeded(context: ModelContext) {
        guard activeConversationID == nil else { return }
        var descriptor = FetchDescriptor<ChatConversation>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        if let conversation = try? context.fetch(descriptor).first {
            loadConversation(conversation)
        } else {
            startNewConversation()
        }
    }

    private func fetchEntries(for conversationID: UUID) -> [ChatEntry] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<ChatEntry>(
            predicate: #Predicate { $0.conversationID == conversationID },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func persist(_ message: ChatMessage) {
        guard let modelContext else { return }
        if activeConversationID == nil {
            startNewConversation()
        }
        guard let activeConversationID else { return }

        modelContext.insert(ChatEntry(
            id: message.id,
            conversationID: activeConversationID,
            role: message.role == .user ? "user" : "assistant",
            text: message.text,
            timestamp: message.timestamp,
            toolActions: message.toolActions
        ))

        updateActiveConversation(with: message)
    }

    private func updateActiveConversation(with message: ChatMessage) {
        guard let modelContext, let activeConversationID else { return }
        let descriptor = FetchDescriptor<ChatConversation>(
            predicate: #Predicate { $0.id == activeConversationID }
        )
        guard let conversation = try? modelContext.fetch(descriptor).first else { return }
        if conversation.title == "New chat", message.role == .user {
            conversation.title = String(message.text.prefix(48))
        }
        conversation.updatedAt = message.timestamp
    }

    // MARK: - Conversation loop

    private func runTurn() async throws -> (String, [String]) {
        var toolActions: [String] = []

        for _ in 0..<8 {
            let json = try await post(body: buildBody())

            guard let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else {
                throw GeminiError.badResponse
            }

            var callParts: [[String: Any]] = []
            var responseParts: [[String: Any]] = []

            for part in parts {
                guard let call = part["functionCall"] as? [String: Any],
                      let name = call["name"] as? String else { continue }
                let args = (call["args"] as? [String: Any]) ?? [:]
                let (result, action) = executeTool(name: name, args: args)
                if let action { toolActions.append(action) }
                callParts.append(part)
                responseParts.append([
                    "functionResponse": ["name": name, "response": ["result": result]]
                ])
            }

            if !callParts.isEmpty {
                history.append(["role": "model", "parts": callParts])
                history.append(["role": "user", "parts": responseParts])
                continue
            }

            let text = parts.compactMap { $0["text"] as? String }.joined()
            return (text.isEmpty ? "Done." : text, toolActions)
        }

        throw GeminiError.loopLimit
    }

    // MARK: - Networking

    private func buildBody() -> [String: Any] {
        [
            "contents": history,
            "systemInstruction": ["parts": [["text": systemPrompt]]],
            "tools": [["functionDeclarations": toolDefinitions]]
        ]
    }

    private func post(body: [String: Any]) async throws -> [String: Any] {
        var lastModelError: String?

        for modelID in modelIDs {
            let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelID):generateContent?key=\(apiKey)")!
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                let message = apiErrorMessage(from: data)
                if shouldTryNextModel(after: message) {
                    lastModelError = message
                    continue
                }

                throw GeminiError.api(message)
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw GeminiError.badResponse
            }
            return json
        }

        throw GeminiError.api(lastModelError ?? "No configured Gemini model is available.")
    }

    private func apiErrorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? "HTTP error"
        }

        return (error["message"] as? String) ?? "Gemini request failed."
    }

    private func shouldTryNextModel(after message: String) -> Bool {
        let lowercasedMessage = message.lowercased()
        return lowercasedMessage.contains("not found")
            || lowercasedMessage.contains("no longer available")
            || lowercasedMessage.contains("not available")
    }

    // MARK: - Tool execution

    private func executeTool(name: String, args: [String: Any]) -> (String, String?) {
        guard let ctx = modelContext else { return ("No database context available.", nil) }
        switch name {
        case "add_recipe":       return toolAddRecipe(args: args, ctx: ctx)
        case "plan_meal":        return toolPlanMeal(args: args, ctx: ctx)
        case "add_shopping_item": return toolAddShoppingItem(args: args, ctx: ctx)
        case "remove_shopping_item": return toolRemoveShoppingItem(args: args, ctx: ctx)
        case "add_store_price": return toolAddStorePrice(args: args, ctx: ctx)
        case "update_store_price": return toolUpdateStorePrice(args: args)
        case "delete_store_price": return toolDeleteStorePrice(args: args, ctx: ctx)
        case "get_recipes":
            let list = recipes.map { "• \($0.title) (\($0.course.rawValue), \($0.servings) servings, \($0.totalMinutes)min)" }.joined(separator: "\n")
            return (list.isEmpty ? "No recipes saved yet." : list, nil)
        case "get_meal_plan":
            let today = Calendar.current.startOfDay(for: .now)
            let upcoming = mealPlans.filter { $0.date >= today }.sorted { $0.date < $1.date }
            let list = upcoming.map { "• \($0.date.formatted(date: .abbreviated, time: .omitted)) \($0.mealSlot.rawValue): \($0.recipeTitle) (\($0.servings) servings)" }.joined(separator: "\n")
            return (list.isEmpty ? "No meals planned yet." : list, nil)
        case "get_shopping_list":
            let open = shoppingItems.filter { !$0.isChecked }
            let list = open.map { "• \($0.name) \($0.quantity) \($0.unit) @ \($0.targetStore.displayName)" }.joined(separator: "\n")
            return (list.isEmpty ? "Shopping list is empty." : list, nil)
        case "get_store_prices":
            return toolGetStorePrices(args: args)
        default:
            return ("Unknown tool: \(name)", nil)
        }
    }

    private func toolAddRecipe(args: [String: Any], ctx: ModelContext) -> (String, String?) {
        guard let title = args["title"] as? String, !title.isEmpty else { return ("Missing title.", nil) }
        let ingredients = (args["ingredients"] as? [String]) ?? []
        if let blockedIngredient = firstAvoidedIngredientMatch(in: [title] + ingredients) {
            return ("I did not save that recipe because it includes \(blockedIngredient), which is listed in your avoided ingredients.", nil)
        }
        let recipe = Recipe(
            title: title,
            summary: (args["summary"] as? String) ?? "",
            servings: (args["servings"] as? Int) ?? 2,
            ingredients: ingredients,
            steps: (args["steps"] as? [String]) ?? [],
            estimatedCost: (args["estimated_cost"] as? Double) ?? 0,
            course: RecipeCourse(rawValue: (args["course"] as? String) ?? "") ?? .dinner,
            difficulty: RecipeDifficulty(rawValue: (args["difficulty"] as? String) ?? "") ?? .easy,
            cuisine: (args["cuisine"] as? String) ?? "",
            tags: (args["tags"] as? [String]) ?? [],
            prepMinutes: (args["prep_minutes"] as? Int) ?? 10,
            cookMinutes: (args["cook_minutes"] as? Int) ?? 20,
            caloriesPerServing: intValue(for: "calories_per_serving", in: args),
            proteinGrams: doubleValue(for: "protein_grams", in: args),
            carbohydrateGrams: doubleValue(for: "carbohydrate_grams", in: args),
            fatGrams: doubleValue(for: "fat_grams", in: args),
            fiberGrams: doubleValue(for: "fiber_grams", in: args)
        )
        ctx.insert(recipe)
        return ("Recipe '\(title)' saved.", "Saved recipe: \(title)")
    }

    private func intValue(for key: String, in args: [String: Any]) -> Int {
        if let value = args[key] as? Int { return value }
        if let value = args[key] as? Double { return Int(value.rounded()) }
        if let value = args[key] as? String, let parsed = Double(value) { return Int(parsed.rounded()) }
        return 0
    }

    private func doubleValue(for key: String, in args: [String: Any]) -> Double {
        if let value = args[key] as? Double { return value }
        if let value = args[key] as? Int { return Double(value) }
        if let value = args[key] as? String, let parsed = Double(value) { return parsed }
        return 0
    }

    private func toolPlanMeal(args: [String: Any], ctx: ModelContext) -> (String, String?) {
        guard let recipeTitle = args["recipe_title"] as? String else { return ("Missing recipe title.", nil) }
        if let blockedIngredient = firstAvoidedIngredientMatch(in: mealPlanSafetyTexts(for: recipeTitle)) {
            return ("I did not add \(recipeTitle) to the meal plan because it appears to include \(blockedIngredient), which is listed in your avoided ingredients.", nil)
        }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let date = df.date(from: (args["date"] as? String) ?? "") ?? .now
        let slot = MealSlot(rawValue: (args["meal_slot"] as? String) ?? "") ?? .dinner
        let servings = (args["servings"] as? Int) ?? 2
        ctx.insert(MealPlanEntry(date: date, mealSlot: slot, recipeTitle: recipeTitle, servings: servings))
        let label = date.formatted(date: .abbreviated, time: .omitted)
        return ("Planned '\(recipeTitle)' for \(label) (\(slot.rawValue)).", "Planned: \(recipeTitle) on \(label)")
    }

    private func toolAddShoppingItem(args: [String: Any], ctx: ModelContext) -> (String, String?) {
        guard let name = args["name"] as? String, !name.isEmpty else { return ("Missing item name.", nil) }
        let store = GroceryStore(rawValue: (args["store"] as? String) ?? "") ?? .rema1000
        let estimatedPrice = doubleValue(for: "estimated_price", in: args)
        let quantity = (args["quantity"] as? String) ?? "1"
        let unit = (args["unit"] as? String) ?? "stk"
        ctx.insert(ShoppingListItem(
            name: name,
            quantity: quantity,
            unit: unit,
            targetStore: store,
            estimatedUnitPrice: estimatedPrice,
            category: ShoppingCategory(rawValue: (args["category"] as? String) ?? "") ?? .other,
            priority: ShoppingPriority(rawValue: (args["priority"] as? String) ?? "") ?? .normal,
            notes: (args["notes"] as? String) ?? ""
        ))
        if estimatedPrice > 0 {
            upsertStorePrice(itemName: name, store: store, price: estimatedPrice, quantity: Double(quantity.replacingOccurrences(of: ",", with: ".")) ?? 1, unit: unit, currency: "NOK", source: "shopping", ctx: ctx)
        }
        return ("Added '\(name)' to shopping list.", "Added to list: \(name)")
    }

    private func toolRemoveShoppingItem(args: [String: Any], ctx: ModelContext) -> (String, String?) {
        guard let name = args["name"] as? String else { return ("Missing item name.", nil) }
        let matches = shoppingItems.filter { $0.name.localizedCaseInsensitiveContains(name) }
        for item in matches { ctx.delete(item) }
        guard !matches.isEmpty else { return ("No item matching '\(name)' found.", nil) }
        return ("Removed \(matches.count) item(s) matching '\(name)'.", "Removed from list: \(name)")
    }

    private func toolGetStorePrices(args: [String: Any]) -> (String, String?) {
        let itemName = (args["item_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let matches = matchingStorePrices(itemName: itemName, storeRawValue: args["store"] as? String)
        let list = matches.prefix(20).map { price in
            "• \(price.itemName) @ \(price.store.displayName): \(price.price.formattedCurrency(code: price.currency)) / \(price.amountDescription) (\(price.source))"
        }.joined(separator: "\n")
        return (list.isEmpty ? "No matching store prices saved." : list, nil)
    }

    private func toolAddStorePrice(args: [String: Any], ctx: ModelContext) -> (String, String?) {
        guard let itemName = args["item_name"] as? String, !itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ("Missing item name.", nil)
        }
        let store = GroceryStore(rawValue: (args["store"] as? String) ?? "") ?? .rema1000
        let price = doubleValue(for: "price", in: args)
        guard price > 0 else { return ("Missing price.", nil) }
        let currency = (args["currency"] as? String) ?? "NOK"
        let quantity = doubleValue(for: "quantity", in: args)
        let unit = (args["unit"] as? String) ?? "stk"
        let source = (args["source"] as? String) ?? "chat"
        upsertStorePrice(itemName: itemName, store: store, price: price, quantity: quantity > 0 ? quantity : 1, unit: unit, currency: currency, source: source, ctx: ctx)
        return ("Saved \(itemName) at \(store.displayName) for \(price.formattedCurrency(code: currency)).", "Saved price: \(itemName) at \(store.displayName)")
    }

    private func upsertStorePrice(itemName: String, store: GroceryStore, price: Double, quantity: Double, unit: String, currency: String, source: String, ctx: ModelContext) {
        if let existing = storePrices.first(where: {
            StorePriceMatcher.normalize($0.itemName) == StorePriceMatcher.normalize(itemName) && $0.storeRawValue == store.rawValue
        }) {
            existing.itemName = itemName
            existing.price = price
            existing.quantity = quantity
            existing.unit = unit
            existing.currency = currency
            existing.source = source
            existing.updatedAt = .now
        } else {
            ctx.insert(StorePrice(itemName: itemName, store: store, price: price, quantity: quantity, unit: unit, currency: currency, source: source))
        }
    }

    private func toolUpdateStorePrice(args: [String: Any]) -> (String, String?) {
        guard let itemName = args["item_name"] as? String else { return ("Missing item name.", nil) }
        let matches = matchingStorePrices(itemName: itemName, storeRawValue: args["store"] as? String)
        guard let priceRecord = matches.first else { return ("No matching price record found.", nil) }

        if let newName = args["new_item_name"] as? String, !newName.isEmpty {
            priceRecord.itemName = newName
        }
        if let storeRawValue = args["new_store"] as? String, let store = GroceryStore(rawValue: storeRawValue) {
            priceRecord.storeRawValue = store.rawValue
        }
        let newPrice = doubleValue(for: "price", in: args)
        if newPrice > 0 {
            priceRecord.price = newPrice
        }
        let newQuantity = doubleValue(for: "quantity", in: args)
        if newQuantity > 0 {
            priceRecord.quantity = newQuantity
        }
        if let unit = args["unit"] as? String, !unit.isEmpty {
            priceRecord.unit = unit
        }
        if let currency = args["currency"] as? String, !currency.isEmpty {
            priceRecord.currency = currency
        }
        if let source = args["source"] as? String, !source.isEmpty {
            priceRecord.source = source
        }
        priceRecord.updatedAt = .now
        return ("Updated \(priceRecord.itemName) at \(priceRecord.store.displayName).", "Updated price: \(priceRecord.itemName)")
    }

    private func toolDeleteStorePrice(args: [String: Any], ctx: ModelContext) -> (String, String?) {
        guard let itemName = args["item_name"] as? String else { return ("Missing item name.", nil) }
        let matches = matchingStorePrices(itemName: itemName, storeRawValue: args["store"] as? String)
        guard !matches.isEmpty else { return ("No matching price records found.", nil) }
        for price in matches {
            ctx.delete(price)
        }
        return ("Deleted \(matches.count) price record(s) for \(itemName).", "Deleted price: \(itemName)")
    }

    private func matchingStorePrices(itemName: String, storeRawValue: String?) -> [StorePrice] {
        let normalizedItemName = StorePriceMatcher.normalize(itemName)
        return storePrices.filter { price in
            let matchesName = normalizedItemName.isEmpty
                || StorePriceMatcher.normalize(price.itemName).contains(normalizedItemName)
                || normalizedItemName.contains(StorePriceMatcher.normalize(price.itemName))
            let matchesStore = storeRawValue == nil || price.storeRawValue == storeRawValue
            return matchesName && matchesStore
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func mealPlanSafetyTexts(for recipeTitle: String) -> [String] {
        guard let recipe = recipes.first(where: { $0.title.localizedCaseInsensitiveCompare(recipeTitle) == .orderedSame }) else {
            return [recipeTitle]
        }
        return [recipe.title, recipe.summary, recipe.cuisine] + recipe.ingredients + recipe.tags
    }

    private func firstAvoidedIngredientMatch(in values: [String]) -> String? {
        let avoidedIngredients = settings?.avoidedIngredients ?? []
        guard !avoidedIngredients.isEmpty else { return nil }
        let normalizedValues = values.map(StorePriceMatcher.normalize).filter { !$0.isEmpty }
        return avoidedIngredients.first { ingredient in
            expandedAvoidedTerms(for: ingredient).contains { term in
                normalizedValues.contains { value in
                    value == term
                        || value.contains(" \(term) ")
                        || value.hasPrefix("\(term) ")
                        || value.hasSuffix(" \(term)")
                }
            }
        }
    }

    private func expandedAvoidedTerms(for ingredient: String) -> [String] {
        let normalizedIngredient = StorePriceMatcher.normalize(ingredient)
        guard !normalizedIngredient.isEmpty else { return [] }
        if ["fish", "seafood", "fisk", "sjømat", "sjomat"].contains(normalizedIngredient) {
            return [
                normalizedIngredient,
                "salmon", "laks", "cod", "torsk", "trout", "orret", "ørret",
                "tuna", "tunfisk", "mackerel", "makrell", "haddock", "hyse",
                "pollock", "sei", "halibut", "kveite", "sardine", "sardin",
                "shrimp", "reker", "prawn", "crab", "krabbe", "mussel", "blaskjell", "blåskjell"
            ]
        }
        return [normalizedIngredient]
    }

    // MARK: - System prompt & tool definitions

    private var systemPrompt: String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let today = df.string(from: .now)
        let recipeList = recipes.prefix(30).map(\.title).joined(separator: ", ")
        let dietaryPreferences = settings?.dietaryPreferences.map { $0.title(language: settings?.preferredLanguage ?? .english) }.joined(separator: ", ") ?? ""
        let avoidedIngredients = settings?.avoidedIngredients.joined(separator: ", ") ?? ""
        let enabledStores = (settings?.enabledStores ?? GroceryStore.defaultTrackedStores).map(\.displayName).joined(separator: ", ")
        let recentPriceRecords = storePrices.prefix(20).map { "\($0.itemName) at \($0.store.displayName): \($0.price.formattedCurrency(code: $0.currency)) per \($0.amountDescription)" }.joined(separator: "; ")
        return """
        You are the built-in assistant for the Meal Planner app. Today is \(today).
        The user has \(recipes.count) recipe(s) saved\(recipeList.isEmpty ? "." : ": \(recipeList).")
        User settings:
        - Language: \(settings?.preferredLanguage.title ?? "English")
        - Household size: \(settings?.householdSize ?? 2)
        - Planning horizon: \(settings?.planningHorizonDays ?? 7) days
        - Weekly grocery budget: \((settings?.weeklyBudget ?? 0).formattedCurrency(code: settings?.currencyCode ?? "NOK"))
        - Currency: \(settings?.currencyCode ?? "NOK")
        - Enabled stores: \(enabledStores)
        - Dietary preferences: \(dietaryPreferences.isEmpty ? "none" : dietaryPreferences)
        - Avoided ingredients: \(avoidedIngredients.isEmpty ? "none" : avoidedIngredients)
        - Prefer cheapest tracked store: \(settings?.preferCheapestTrackedStore ?? true)
        - Auto-add recipe ingredients to shopping list: \(settings?.autoAddIngredientsToShoppingList ?? true)
        Recent tracked prices: \(recentPriceRecords.isEmpty ? "none" : recentPriceRecords)
        Your job is limited to meal planning, recipes, grocery shopping, receipt/price tracking, and helping the user operate this app.
        If the user asks for anything outside that scope, briefly say you can only help with meal planning and app-related food tasks, then offer a relevant app action.
        Do not answer general knowledge, coding, entertainment, medical, legal, financial, or unrelated personal-assistant requests.
        Use the available tools when the user asks to add, remove, list, or plan app data. Confirm what changed after a tool succeeds.
        Never add recipes, meals, or shopping suggestions containing avoided ingredients. If a user asks for one, explain that it conflicts with their settings and offer an alternative.
        When planning meals, honor dietary preferences, avoided ingredients, household size, weekly budget, enabled stores, and tracked store prices.
        When shopping or comparing prices, prefer enabled stores and use saved StorePrice records when available.
        When adding a recipe, always include full ingredients, step-by-step instructions, and estimated nutrition per serving.
        Nutrition per serving must include calories_per_serving, protein_grams, carbohydrate_grams, fat_grams, and fiber_grams.
        For dates use YYYY-MM-DD. For stores use rawValues like: rema1000, kiwi, meny, coopExtra, spar, coopPrix, bunnpris.
        Keep responses concise, practical, and focused on the user's meal planning workflow.
        """
    }

    private var toolDefinitions: [[String: Any]] {
        [
            [
                "name": "add_recipe",
                "description": "Save a new recipe to the app",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string"],
                        "summary": ["type": "string"],
                        "servings": ["type": "integer"],
                        "ingredients": ["type": "array", "items": ["type": "string"]],
                        "steps": ["type": "array", "items": ["type": "string"]],
                        "estimated_cost": ["type": "number", "description": "Cost in local currency"],
                        "course": ["type": "string", "enum": ["breakfast", "lunch", "dinner", "dessert", "snack", "side"]],
                        "difficulty": ["type": "string", "enum": ["easy", "medium", "hard"]],
                        "cuisine": ["type": "string"],
                        "tags": ["type": "array", "items": ["type": "string"]],
                        "prep_minutes": ["type": "integer"],
                        "cook_minutes": ["type": "integer"],
                        "calories_per_serving": ["type": "integer", "description": "Estimated kcal per serving"],
                        "protein_grams": ["type": "number", "description": "Estimated grams of protein per serving"],
                        "carbohydrate_grams": ["type": "number", "description": "Estimated grams of carbohydrates per serving"],
                        "fat_grams": ["type": "number", "description": "Estimated grams of fat per serving"],
                        "fiber_grams": ["type": "number", "description": "Estimated grams of fiber per serving"]
                    ] as [String: Any],
                    "required": ["title", "ingredients", "steps", "calories_per_serving", "protein_grams", "carbohydrate_grams", "fat_grams", "fiber_grams"]
                ] as [String: Any]
            ],
            [
                "name": "plan_meal",
                "description": "Plan a meal for a specific date",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "recipe_title": ["type": "string"],
                        "date": ["type": "string", "description": "YYYY-MM-DD"],
                        "meal_slot": ["type": "string", "enum": ["breakfast", "lunch", "dinner", "snack"]],
                        "servings": ["type": "integer"]
                    ] as [String: Any],
                    "required": ["recipe_title", "date", "meal_slot"]
                ] as [String: Any]
            ],
            [
                "name": "add_shopping_item",
                "description": "Add an item to the shopping list",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string"],
                        "quantity": ["type": "string"],
                        "unit": ["type": "string"],
                        "store": ["type": "string", "description": "Store rawValue e.g. rema1000, kiwi, meny"],
                        "estimated_price": ["type": "number"],
                        "category": ["type": "string", "enum": ["produce", "meatSeafood", "dairy", "bakery", "pantry", "frozen", "household", "personalCare", "other"]],
                        "priority": ["type": "string", "enum": ["low", "normal", "high"]],
                        "notes": ["type": "string"]
                    ] as [String: Any],
                    "required": ["name"]
                ] as [String: Any]
            ],
            [
                "name": "remove_shopping_item",
                "description": "Remove an item from the shopping list",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string", "description": "Item name or partial match"]
                    ] as [String: Any],
                    "required": ["name"]
                ] as [String: Any]
            ],
            [
                "name": "get_store_prices",
                "description": "List saved supermarket price records, optionally filtered by item name and store",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "item_name": ["type": "string", "description": "Optional item name or partial match"],
                        "store": ["type": "string", "description": "Optional store rawValue e.g. rema1000, kiwi, meny"]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            [
                "name": "add_store_price",
                "description": "Add a supermarket price record for an item at a store",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "item_name": ["type": "string"],
                        "store": ["type": "string", "description": "Store rawValue e.g. rema1000, kiwi, meny"],
                        "price": ["type": "number"],
                        "quantity": ["type": "number", "description": "Package quantity, default 1"],
                        "unit": ["type": "string", "description": "Package unit, default stk"],
                        "currency": ["type": "string", "description": "Currency code, default NOK"],
                        "source": ["type": "string", "description": "Where the price came from, default chat"]
                    ] as [String: Any],
                    "required": ["item_name", "store", "price"]
                ] as [String: Any]
            ],
            [
                "name": "update_store_price",
                "description": "Update the newest matching supermarket price record",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "item_name": ["type": "string", "description": "Current item name or partial match"],
                        "store": ["type": "string", "description": "Optional current store rawValue to narrow the match"],
                        "new_item_name": ["type": "string"],
                        "new_store": ["type": "string"],
                        "price": ["type": "number"],
                        "quantity": ["type": "number"],
                        "unit": ["type": "string"],
                        "currency": ["type": "string"],
                        "source": ["type": "string"]
                    ] as [String: Any],
                    "required": ["item_name"]
                ] as [String: Any]
            ],
            [
                "name": "delete_store_price",
                "description": "Delete matching supermarket price records",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "item_name": ["type": "string", "description": "Item name or partial match"],
                        "store": ["type": "string", "description": "Optional store rawValue to narrow deletion"]
                    ] as [String: Any],
                    "required": ["item_name"]
                ] as [String: Any]
            ],
            [
                "name": "get_recipes",
                "description": "List all saved recipes",
                "parameters": ["type": "object", "properties": [:] as [String: Any]]
            ],
            [
                "name": "get_meal_plan",
                "description": "Get upcoming planned meals",
                "parameters": ["type": "object", "properties": [:] as [String: Any]]
            ],
            [
                "name": "get_shopping_list",
                "description": "Get current shopping list",
                "parameters": ["type": "object", "properties": [:] as [String: Any]]
            ]
        ]
    }
}

enum GeminiError: LocalizedError {
    case badResponse, loopLimit
    case api(String)

    var errorDescription: String? {
        switch self {
        case .badResponse: "Unexpected response from Gemini"
        case .loopLimit: "Too many tool calls in one response"
        case .api(let msg): msg
        }
    }
}
