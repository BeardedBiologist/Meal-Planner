import PhotosUI
import SwiftData
import SwiftUI
@preconcurrency import Vision

struct MealPlannerHomeView: View {
    private let authManager = AuthenticationManager.shared
    @Environment(\.modelContext) private var modelContext
    @State private var language: AppLanguage = .english

    var body: some View {
        TabView {
            DashboardView(language: language)
                .tabItem { Label(text("Overview", "Oversikt"), systemImage: "chart.bar") }

            MealPlanView(language: language)
                .tabItem { Label(text("Plan", "Plan"), systemImage: "calendar") }

            RecipesView(language: language)
                .tabItem { Label(text("Recipes", "Oppskrifter"), systemImage: "book.closed") }

            ShoppingListView(language: language)
                .tabItem { Label(text("Shopping", "Handleliste"), systemImage: "cart") }

            ReceiptScannerView(language: language)
                .tabItem { Label(text("Receipts", "Kvitteringer"), systemImage: "doc.text.viewfinder") }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Picker("Language", selection: $language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    authManager.signOut()
                } label: {
                    Label(text("Sign Out", "Logg ut"), systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private struct DashboardView: View {
    let language: AppLanguage
    @Query private var recipes: [Recipe]
    @Query private var mealPlans: [MealPlanEntry]
    @Query private var shoppingItems: [ShoppingListItem]
    @Query private var receiptItems: [ReceiptLineItem]

    private var openShoppingTotal: Double {
        shoppingItems.filter { !$0.isChecked }.reduce(0) { $0 + $1.estimatedUnitPrice }
    }

    private var receiptTotal: Double {
        receiptItems.reduce(0) { $0 + $1.price }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        MetricTile(title: text("Open list", "Åpen liste"), value: openShoppingTotal.formattedNOK, icon: "cart")
                        MetricTile(title: text("Receipts", "Kvitteringer"), value: receiptTotal.formattedNOK, icon: "receipt")
                    }
                    HStack(spacing: 12) {
                        MetricTile(title: text("Recipes", "Oppskrifter"), value: "\(recipes.count)", icon: "book.closed")
                        MetricTile(title: text("Meals planned", "Måltider planlagt"), value: "\(mealPlans.count)", icon: "calendar")
                    }
                }

                Section(text("Best store coverage", "Butikkoversikt")) {
                    ForEach(GroceryStore.allCases) { store in
                        let count = receiptItems.filter { $0.storeRawValue == store.rawValue }.count
                        Label("\(store.displayName): \(count) " + text("priced items", "prisede varer"), systemImage: "tag")
                    }
                }

                Section(text("Next steps", "Neste steg")) {
                    Text(text("Add a few recipes, plan meals for the week, then scan receipts after shopping so the app learns real prices for Coop Extra, Meny, and Rema 1000.", "Legg inn noen oppskrifter, planlegg ukens måltider, og skann kvitteringer etter handling slik at appen lærer faktiske priser hos Coop Extra, Meny og Rema 1000."))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(text("Meal Planner", "Måltidsplanlegger"))
        }
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MealPlanView: View {
    let language: AppLanguage
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MealPlanEntry.date) private var mealPlans: [MealPlanEntry]
    @Query(sort: \Recipe.title) private var recipes: [Recipe]
    @State private var showAddMeal = false

    var body: some View {
        NavigationStack {
            List {
                if mealPlans.isEmpty {
                    ContentUnavailableView(text("No meals planned", "Ingen måltider planlagt"), systemImage: "calendar.badge.plus", description: Text(text("Add meals for a week or month and generate your shopping list from recipes.", "Legg inn måltider for en uke eller måned og lag handlelisten fra oppskriftene.")))
                } else {
                    ForEach(mealPlans) { plan in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plan.recipeTitle)
                                .font(.headline)
                            Text("\(plan.date.formatted(date: .abbreviated, time: .omitted)) · \(plan.mealSlot.title(language: language)) · \(plan.servings) " + text("servings", "porsjoner"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: deleteMealPlans)
                }
            }
            .navigationTitle(text("Meal Plan", "Måltidsplan"))
            .toolbar {
                Button {
                    showAddMeal = true
                } label: {
                    Label(text("Add Meal", "Legg til"), systemImage: "plus")
                }
            }
            .sheet(isPresented: $showAddMeal) {
                AddMealPlanView(language: language)
            }
        }
    }

    private func deleteMealPlans(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(mealPlans[index])
        }
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private struct AddMealPlanView: View {
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.title) private var recipes: [Recipe]
    @State private var date = Date()
    @State private var mealSlot: MealSlot = .dinner
    @State private var recipeTitle = ""
    @State private var servings = 2

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(text("Date", "Dato"), selection: $date, displayedComponents: .date)
                Picker(text("Meal", "Måltid"), selection: $mealSlot) {
                    ForEach(MealSlot.allCases) { slot in
                        Text(slot.title(language: language)).tag(slot)
                    }
                }

                if recipes.isEmpty {
                    TextField(text("Recipe name", "Oppskriftsnavn"), text: $recipeTitle)
                } else {
                    Picker(text("Recipe", "Oppskrift"), selection: $recipeTitle) {
                        Text(text("Choose recipe", "Velg oppskrift")).tag("")
                        ForEach(recipes) { recipe in
                            Text(recipe.title).tag(recipe.title)
                        }
                    }
                }

                Stepper("\(servings) " + text("servings", "porsjoner"), value: $servings, in: 1...12)
            }
            .navigationTitle(text("Plan Meal", "Planlegg måltid"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(text("Cancel", "Avbryt")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(text("Save", "Lagre"), action: save)
                        .disabled(recipeTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if recipeTitle.isEmpty, let firstRecipe = recipes.first {
                    recipeTitle = firstRecipe.title
                }
            }
        }
    }

    private func save() {
        modelContext.insert(MealPlanEntry(date: date, mealSlot: mealSlot, recipeTitle: recipeTitle, servings: servings))
        if let recipe = recipes.first(where: { $0.title == recipeTitle }) {
            addIngredientsToShoppingList(from: recipe)
        }
        dismiss()
    }

    private func addIngredientsToShoppingList(from recipe: Recipe) {
        for ingredient in recipe.ingredients where !ingredient.isEmpty {
            modelContext.insert(ShoppingListItem(name: ingredient, quantity: "1", unit: text("item", "vare"), targetStore: .rema1000, estimatedUnitPrice: 0, sourceRecipeTitle: recipe.title))
        }
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private struct RecipesView: View {
    let language: AppLanguage
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.title) private var recipes: [Recipe]
    @State private var showAddRecipe = false

    var body: some View {
        NavigationStack {
            List {
                if recipes.isEmpty {
                    ContentUnavailableView(text("No recipes saved", "Ingen oppskrifter lagret"), systemImage: "book.closed", description: Text(text("Save recipes with ingredients so planned meals can add to your shopping list.", "Lagre oppskrifter med ingredienser slik at planlagte måltider kan legges til handlelisten.")))
                } else {
                    ForEach(recipes) { recipe in
                        NavigationLink {
                            RecipeDetailView(recipe: recipe, language: language)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recipe.title)
                                    .font(.headline)
                                Text("\(recipe.servings) " + text("servings", "porsjoner") + " · " + recipe.estimatedCost.formattedNOK)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: deleteRecipes)
                }
            }
            .navigationTitle(text("Recipes", "Oppskrifter"))
            .toolbar {
                Button {
                    showAddRecipe = true
                } label: {
                    Label(text("Add Recipe", "Legg til"), systemImage: "plus")
                }
            }
            .sheet(isPresented: $showAddRecipe) {
                AddRecipeView(language: language)
            }
        }
    }

    private func deleteRecipes(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(recipes[index])
        }
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private struct RecipeDetailView: View {
    let recipe: Recipe
    let language: AppLanguage

    var body: some View {
        List {
            Section(text("Summary", "Sammendrag")) {
                Text(recipe.summary.isEmpty ? text("No summary added.", "Ingen sammendrag lagt til.") : recipe.summary)
                Label("\(recipe.servings) " + text("servings", "porsjoner"), systemImage: "person.2")
                Label(recipe.estimatedCost.formattedNOK, systemImage: "creditcard")
            }

            Section(text("Ingredients", "Ingredienser")) {
                ForEach(recipe.ingredients, id: \.self) { ingredient in
                    Text(ingredient)
                }
            }

            Section(text("Steps", "Fremgangsmåte")) {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(step)")
                }
            }
        }
        .navigationTitle(recipe.title)
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private struct AddRecipeView: View {
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var title = ""
    @State private var summary = ""
    @State private var servings = 2
    @State private var ingredientsText = ""
    @State private var stepsText = ""
    @State private var estimatedCost = 0.0

    var body: some View {
        NavigationStack {
            Form {
                Section(text("Recipe", "Oppskrift")) {
                    TextField(text("Title", "Tittel"), text: $title)
                    TextField(text("Summary", "Sammendrag"), text: $summary, axis: .vertical)
                    Stepper("\(servings) " + text("servings", "porsjoner"), value: $servings, in: 1...12)
                    TextField(text("Estimated cost", "Estimert kostnad"), value: $estimatedCost, format: .number)
                        .keyboardType(.decimalPad)
                }

                Section(text("Ingredients", "Ingredienser")) {
                    TextField(text("One ingredient per line", "Én ingrediens per linje"), text: $ingredientsText, axis: .vertical)
                        .lineLimit(6, reservesSpace: true)
                }

                Section(text("Steps", "Fremgangsmåte")) {
                    TextField(text("One step per line", "Ett steg per linje"), text: $stepsText, axis: .vertical)
                        .lineLimit(5, reservesSpace: true)
                }
            }
            .navigationTitle(text("New Recipe", "Ny oppskrift"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(text("Cancel", "Avbryt")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(text("Save", "Lagre"), action: save)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let ingredients = splitLines(ingredientsText)
        let steps = splitLines(stepsText)
        modelContext.insert(Recipe(title: title, summary: summary, servings: servings, ingredients: ingredients, steps: steps, estimatedCost: estimatedCost))
        dismiss()
    }

    private func splitLines(_ value: String) -> [String] {
        value.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private struct ShoppingListView: View {
    let language: AppLanguage
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ShoppingListItem.createdAt) private var items: [ShoppingListItem]
    @State private var showAddItem = false

    private var total: Double {
        items.filter { !$0.isChecked }.reduce(0) { $0 + $1.estimatedUnitPrice }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(text("Estimated open total", "Estimert åpen total") + ": " + total.formattedNOK, systemImage: "creditcard")
                }

                if items.isEmpty {
                    ContentUnavailableView(text("Shopping list is empty", "Handlelisten er tom"), systemImage: "cart", description: Text(text("Plan meals or add grocery items manually.", "Planlegg måltider eller legg inn varer manuelt.")))
                } else {
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Button {
                                item.isChecked.toggle()
                            } label: {
                                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                                    .imageScale(.large)
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.headline)
                                    .strikethrough(item.isChecked)
                                Text("\(item.quantity) \(item.unit) · \(item.targetStore.displayName) · \(item.estimatedUnitPrice.formattedNOK)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if !item.sourceRecipeTitle.isEmpty {
                                    Text(item.sourceRecipeTitle)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    .onDelete(perform: deleteItems)
                }
            }
            .navigationTitle(text("Shopping List", "Handleliste"))
            .toolbar {
                Button {
                    showAddItem = true
                } label: {
                    Label(text("Add Item", "Legg til"), systemImage: "plus")
                }
            }
            .sheet(isPresented: $showAddItem) {
                AddShoppingItemView(language: language)
            }
        }
    }

    private func deleteItems(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(items[index])
        }
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private struct AddShoppingItemView: View {
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var quantity = "1"
    @State private var unit = "stk"
    @State private var store: GroceryStore = .rema1000
    @State private var estimatedPrice = 0.0

    var body: some View {
        NavigationStack {
            Form {
                TextField(text("Item", "Vare"), text: $name)
                HStack {
                    TextField(text("Quantity", "Antall"), text: $quantity)
                    TextField(text("Unit", "Enhet"), text: $unit)
                }
                Picker(text("Store", "Butikk"), selection: $store) {
                    ForEach(GroceryStore.allCases) { store in
                        Text(store.displayName).tag(store)
                    }
                }
                TextField(text("Estimated price", "Estimert pris"), value: $estimatedPrice, format: .number)
                    .keyboardType(.decimalPad)
            }
            .navigationTitle(text("New Item", "Ny vare"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(text("Cancel", "Avbryt")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(text("Save", "Lagre"), action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        modelContext.insert(ShoppingListItem(name: name, quantity: quantity, unit: unit, targetStore: store, estimatedUnitPrice: estimatedPrice))
        dismiss()
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private struct ReceiptScannerView: View {
    let language: AppLanguage
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ReceiptLineItem.purchasedAt, order: .reverse) private var receiptItems: [ReceiptLineItem]
    @State private var selectedStore: GroceryStore = .rema1000
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var recognizedLines: [ParsedReceiptLine] = []
    @State private var isScanning = false
    @State private var scanError: String?

    var body: some View {
        NavigationStack {
            List {
                Section(text("Scan receipt", "Skann kvittering")) {
                    Picker(text("Store", "Butikk"), selection: $selectedStore) {
                        ForEach(GroceryStore.allCases) { store in
                            Text(store.displayName).tag(store)
                        }
                    }

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(text("Choose Receipt Image", "Velg kvitteringsbilde"), systemImage: "photo")
                    }

                    if isScanning {
                        ProgressView(text("Reading receipt...", "Leser kvittering..."))
                    }

                    if let scanError {
                        Text(scanError)
                            .foregroundStyle(.red)
                    }
                }

                if !recognizedLines.isEmpty {
                    Section(text("Recognized items", "Gjenkjente varer")) {
                        ForEach(recognizedLines) { line in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(line.name)
                                    Text(line.rawText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(line.price.formattedNOK)
                            }
                        }

                        Button {
                            saveRecognizedItems()
                        } label: {
                            Label(text("Save Prices", "Lagre priser"), systemImage: "tray.and.arrow.down")
                        }
                    }
                }

                Section(text("Saved receipt prices", "Lagrede kvitteringspriser")) {
                    if receiptItems.isEmpty {
                        Text(text("No receipt prices saved yet.", "Ingen kvitteringspriser lagret ennå."))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(receiptItems) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.itemName)
                                        .font(.headline)
                                    Text("\(item.store.displayName) · \(item.purchasedAt.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(item.price.formattedNOK)
                            }
                        }
                    }
                }
            }
            .navigationTitle(text("Receipts", "Kvitteringer"))
            .onChange(of: selectedPhoto) { _, newValue in
                guard let newValue else { return }
                Task { await scanReceipt(from: newValue) }
            }
        }
    }

    private func scanReceipt(from item: PhotosPickerItem) async {
        isScanning = true
        scanError = nil
        recognizedLines = []

        do {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data), let cgImage = image.cgImage else {
                scanError = text("Could not load that image.", "Kunne ikke laste bildet.")
                isScanning = false
                return
            }

            let lines = try await ReceiptTextRecognizer.recognizeText(in: cgImage)
            recognizedLines = ReceiptParser.parse(lines: lines)
            if recognizedLines.isEmpty {
                scanError = text("No priced items were found. Try a clearer photo or add items manually.", "Fant ingen varer med pris. Prøv et tydeligere bilde eller legg inn varer manuelt.")
            }
        } catch {
            scanError = error.localizedDescription
        }

        isScanning = false
    }

    private func saveRecognizedItems() {
        for line in recognizedLines {
            modelContext.insert(ReceiptLineItem(itemName: line.name, price: line.price, store: selectedStore, rawText: line.rawText))
            modelContext.insert(StorePrice(itemName: line.name, store: selectedStore, price: line.price))
        }
        recognizedLines = []
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private struct ParsedReceiptLine: Identifiable {
    let id = UUID()
    let name: String
    let price: Double
    let rawText: String
}

private enum ReceiptParser {
    static func parse(lines: [String]) -> [ParsedReceiptLine] {
        lines.compactMap { line in
            let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleaned.count > 3, let match = priceMatch(in: cleaned) else { return nil }

            let name = cleaned.replacingOccurrences(of: match.original, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !ignoredReceiptLine(name) else { return nil }

            return ParsedReceiptLine(name: name, price: match.price, rawText: cleaned)
        }
    }

    private static func priceMatch(in line: String) -> (original: String, price: Double)? {
        let pattern = #"(\d+[,.]\d{2})\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern), let result = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)), let range = Range(result.range(at: 1), in: line) else {
            return nil
        }

        let original = String(line[range])
        let normalized = original.replacingOccurrences(of: ",", with: ".")
        guard let price = Double(normalized) else { return nil }
        return (original, price)
    }

    private static func ignoredReceiptLine(_ value: String) -> Bool {
        let uppercased = value.uppercased()
        return ["SUM", "TOTAL", "MVA", "BANK", "VISA", "KORT", "BETALT", "ORG", "KVITTERING"].contains { uppercased.contains($0) }
    }
}

private enum ReceiptTextRecognizer {
    static func recognizeText(in image: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }
                continuation.resume(returning: lines)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["nb-NO", "en-US"]
            request.usesLanguageCorrection = true

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: image).perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private extension Double {
    var formattedNOK: String {
        formatted(.currency(code: "NOK"))
    }
}
