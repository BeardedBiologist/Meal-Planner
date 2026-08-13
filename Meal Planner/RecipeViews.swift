import SwiftData
import SwiftUI

struct RecipesView: View {
    let language: AppLanguage
    let currencyCode: String
    let enabledStores: [GroceryStore]
    let defaultServings: Int
    let autoAddIngredientsToShoppingList: Bool
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.title) private var recipes: [Recipe]
    @Query(sort: \StorePrice.updatedAt, order: .reverse) private var storePrices: [StorePrice]
    @State private var showAddRecipe = false
    @State private var searchText = ""
    @State private var filter: RecipeFilter = .all
    @State private var sortMode: RecipeSortMode = .name

    private var filteredRecipes: [Recipe] {
        recipes
            .filter(matchesSearch)
            .filter(matchesFilter)
            .sorted(by: sortRecipes)
    }

    private var favoriteCount: Int {
        recipes.filter(\.isFavorite).count
    }

    private var averageCost: Double {
        guard !recipes.isEmpty else { return 0 }
        return recipes.reduce(0) { $0 + $1.estimatedCost } / Double(recipes.count)
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                controlsSection

                if filteredRecipes.isEmpty {
                    ContentUnavailableView(text("No recipes found", "Fant ingen oppskrifter"), systemImage: "book.closed", description: Text(text("Add recipes with ingredients, costs, tags, and nutrition so planning and shopping can use them.", "Legg inn oppskrifter med ingredienser, kostnad, etiketter og næring slik at plan og handleliste kan bruke dem.")))
                } else {
                    ForEach(filteredRecipes) { recipe in
                        NavigationLink {
                            RecipeDetailView(recipe: recipe, language: language, currencyCode: currencyCode, enabledStores: enabledStores, defaultServings: defaultServings, autoAddIngredientsToShoppingList: autoAddIngredientsToShoppingList, storePrices: storePrices)
                        } label: {
                            RecipeRow(recipe: recipe, language: language, currencyCode: currencyCode)
                        }
                    }
                    .onDelete(perform: deleteRecipes)
                }
            }
            .navigationTitle(text("Recipes", "Oppskrifter"))
            .searchable(text: $searchText, prompt: text("Search recipes", "Søk i oppskrifter"))
            .toolbar {
                Button {
                    showAddRecipe = true
                } label: {
                    Label(text("Add Recipe", "Legg til"), systemImage: "plus")
                }
            }
            .sheet(isPresented: $showAddRecipe) {
                AddRecipeView(language: language, currencyCode: currencyCode)
            }
        }
    }

    private var summarySection: some View {
        Section {
            HStack(spacing: 12) {
                RecipeMetricTile(title: text("Recipes", "Oppskrifter"), value: "\(recipes.count)", icon: "book.closed")
                RecipeMetricTile(title: text("Favorites", "Favoritter"), value: "\(favoriteCount)", icon: "heart")
            }
            HStack(spacing: 12) {
                RecipeMetricTile(title: text("Avg. cost", "Snittkost"), value: averageCost.formattedCurrency(code: currencyCode), icon: "creditcard")
                RecipeMetricTile(title: text("Tags", "Etiketter"), value: "\(Set(recipes.flatMap(\.tags)).count)", icon: "tag")
            }
        }
    }

    private var controlsSection: some View {
        Section(text("View options", "Visningsvalg")) {
            Picker(text("Filter", "Filter"), selection: $filter) {
                ForEach(RecipeFilter.allCases) { filter in
                    Text(filter.title(language: language)).tag(filter)
                }
            }
            Picker(text("Sort", "Sorter"), selection: $sortMode) {
                ForEach(RecipeSortMode.allCases) { mode in
                    Text(mode.title(language: language)).tag(mode)
                }
            }
        }
    }

    private func matchesSearch(_ recipe: Recipe) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let haystack = ([recipe.title, recipe.summary, recipe.cuisine, recipe.notes] + recipe.ingredients + recipe.tags).joined(separator: " ")
        return haystack.localizedCaseInsensitiveContains(query)
    }

    private func matchesFilter(_ recipe: Recipe) -> Bool {
        switch filter {
        case .all: true
        case .favorites: recipe.isFavorite
        case .quick: recipe.totalMinutes <= 30
        case .cheap: recipe.estimatedCost > 0 && recipe.estimatedCost <= averageCost
        case .highProtein: recipe.proteinGrams >= 25
        case .notCookedRecently: recipe.lastCookedAt == nil || (recipe.lastCookedAt ?? .distantPast) < Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        }
    }

    private func sortRecipes(_ lhs: Recipe, _ rhs: Recipe) -> Bool {
        switch sortMode {
        case .name:
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        case .costLowToHigh:
            lhs.estimatedCost < rhs.estimatedCost
        case .quickest:
            lhs.totalMinutes < rhs.totalMinutes
        case .newest:
            lhs.createdAt > rhs.createdAt
        case .mostCooked:
            lhs.timesCooked > rhs.timesCooked
        }
    }

    private func deleteRecipes(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredRecipes[index])
        }
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private struct RecipeDetailView: View {
    @Bindable var recipe: Recipe
    let language: AppLanguage
    let currencyCode: String
    let enabledStores: [GroceryStore]
    let defaultServings: Int
    let autoAddIngredientsToShoppingList: Bool
    let storePrices: [StorePrice]
    @Environment(\.modelContext) private var modelContext
    @State private var showPlanSheet = false
    @State private var showEditSheet = false

    var body: some View {
        List {
            Section(text("Summary", "Sammendrag")) {
                Text(recipe.summary.isEmpty ? text("No summary added.", "Ingen sammendrag lagt til.") : recipe.summary)
                Label("\(recipe.servings) " + text("servings", "porsjoner"), systemImage: "person.2")
                Label(recipe.estimatedCost.formattedCurrency(code: currencyCode), systemImage: "creditcard")
                Label("\(recipe.totalMinutes) " + text("min", "min"), systemImage: "clock")
                Label(recipe.course.title(language: language) + " · " + recipe.difficulty.title(language: language), systemImage: "fork.knife")
                if !recipe.cuisine.isEmpty {
                    Label(recipe.cuisine, systemImage: "globe.europe.africa")
                }
            }

            Section(text("Actions", "Handlinger")) {
                Button {
                    showPlanSheet = true
                } label: {
                    Label(text("Plan this recipe", "Planlegg denne oppskriften"), systemImage: "calendar.badge.plus")
                }

                Button {
                    addIngredientsToShoppingList()
                } label: {
                    Label(text("Add ingredients to shopping list", "Legg ingredienser til handlelisten"), systemImage: "cart.badge.plus")
                }

                Button {
                    markCooked()
                } label: {
                    Label(text("Mark cooked", "Marker som laget"), systemImage: "checkmark.seal")
                }
            }

            if !recipe.tags.isEmpty {
                Section(text("Tags", "Etiketter")) {
                    FlowText(items: recipe.tags)
                }
            }

            Section(text("Nutrition per serving", "Næring per porsjon")) {
                Label("\(recipe.caloriesPerServing) kcal", systemImage: "flame")
                Label("\(recipe.proteinGrams.formatted()) g " + text("protein", "protein"), systemImage: "bolt")
                Label("\(recipe.carbohydrateGrams.formatted()) g " + text("carbs", "karbohydrater"), systemImage: "leaf")
                Label("\(recipe.fatGrams.formatted()) g " + text("fat", "fett"), systemImage: "drop")
                Label("\(recipe.fiberGrams.formatted()) g " + text("fiber", "fiber"), systemImage: "circle.grid.cross")
            }

            Section(text("Ingredients", "Ingredienser")) {
                ForEach(recipe.ingredients, id: \.self) { ingredient in
                    HStack {
                        Text(ingredient)
                        Spacer()
                        if let option = StorePriceMatcher.cheapestOption(for: ingredient, prices: storePrices, enabledStores: enabledStores) {
                            Text("\(option.store.displayName) · \(option.price.formattedCurrency(code: currencyCode))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(text("Steps", "Fremgangsmåte")) {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(step)")
                }
            }

            Section(text("Source and notes", "Kilde og notater")) {
                if !recipe.sourceName.isEmpty {
                    Label(recipe.sourceName, systemImage: "link")
                }
                if !recipe.sourceURL.isEmpty {
                    Text(recipe.sourceURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(recipe.notes.isEmpty ? text("No notes added.", "Ingen notater lagt til.") : recipe.notes)
            }
        }
        .navigationTitle(recipe.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    recipe.isFavorite.toggle()
                } label: {
                    Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showEditSheet = true
                } label: {
                    Label(text("Edit", "Rediger"), systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $showPlanSheet) {
            PlanRecipeSheet(recipe: recipe, language: language, defaultServings: defaultServings, autoAddIngredientsToShoppingList: autoAddIngredientsToShoppingList, enabledStores: enabledStores, storePrices: storePrices)
        }
        .sheet(isPresented: $showEditSheet) {
            EditRecipeView(recipe: recipe, language: language, currencyCode: currencyCode)
        }
    }

    private func markCooked() {
        recipe.timesCooked += 1
        recipe.lastCookedAt = .now
    }

    private func addIngredientsToShoppingList() {
        for ingredient in recipe.ingredients where !ingredient.isEmpty {
            let option = StorePriceMatcher.cheapestOption(for: ingredient, prices: storePrices, enabledStores: enabledStores)
            modelContext.insert(ShoppingListItem(name: ingredient, quantity: "1", unit: text("item", "vare"), targetStore: option?.store ?? enabledStores.first ?? .rema1000, estimatedUnitPrice: option?.price ?? 0, sourceRecipeTitle: recipe.title, category: .other, priority: .normal))
        }
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private struct AddRecipeView: View {
    let language: AppLanguage
    let currencyCode: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var draft = RecipeDraft()

    var body: some View {
        RecipeFormView(language: language, currencyCode: currencyCode, title: text("New Recipe", "Ny oppskrift"), draft: $draft) {
            modelContext.insert(draft.makeRecipe())
            dismiss()
        } cancel: {
            dismiss()
        }
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private struct EditRecipeView: View {
    @Bindable var recipe: Recipe
    let language: AppLanguage
    let currencyCode: String
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RecipeDraft

    init(recipe: Recipe, language: AppLanguage, currencyCode: String) {
        self.recipe = recipe
        self.language = language
        self.currencyCode = currencyCode
        _draft = State(initialValue: RecipeDraft(recipe: recipe))
    }

    var body: some View {
        RecipeFormView(language: language, currencyCode: currencyCode, title: text("Edit Recipe", "Rediger oppskrift"), draft: $draft) {
            draft.apply(to: recipe)
            dismiss()
        } cancel: {
            dismiss()
        }
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private struct RecipeFormView: View {
    let language: AppLanguage
    let currencyCode: String
    let title: String
    @Binding var draft: RecipeDraft
    let save: () -> Void
    let cancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(text("Recipe", "Oppskrift")) {
                    TextField(text("Title", "Tittel"), text: $draft.title)
                    TextField(text("Summary", "Sammendrag"), text: $draft.summary, axis: .vertical)
                    Stepper("\(draft.servings) " + text("servings", "porsjoner"), value: $draft.servings, in: 1...24)
                    TextField(text("Estimated cost", "Estimert kostnad") + " (\(currencyCode))", value: $draft.estimatedCost, format: .number)
                        .keyboardType(.decimalPad)
                    Picker(text("Course", "Måltidstype"), selection: $draft.course) {
                        ForEach(RecipeCourse.allCases) { course in
                            Text(course.title(language: language)).tag(course)
                        }
                    }
                    Picker(text("Difficulty", "Vanskelighetsgrad"), selection: $draft.difficulty) {
                        ForEach(RecipeDifficulty.allCases) { difficulty in
                            Text(difficulty.title(language: language)).tag(difficulty)
                        }
                    }
                    TextField(text("Cuisine", "Kjøkken"), text: $draft.cuisine)
                }

                Section(text("Timing", "Tid")) {
                    Stepper("\(draft.prepMinutes) " + text("min prep", "min forberedelse"), value: $draft.prepMinutes, in: 0...240, step: 5)
                    Stepper("\(draft.cookMinutes) " + text("min cook", "min tilberedning"), value: $draft.cookMinutes, in: 0...360, step: 5)
                }

                Section(text("Nutrition", "Næring")) {
                    TextField("kcal", value: $draft.caloriesPerServing, format: .number)
                        .keyboardType(.numberPad)
                    TextField(text("Protein grams", "Gram protein"), value: $draft.proteinGrams, format: .number)
                        .keyboardType(.decimalPad)
                    TextField(text("Carb grams", "Gram karbohydrater"), value: $draft.carbohydrateGrams, format: .number)
                        .keyboardType(.decimalPad)
                    TextField(text("Fat grams", "Gram fett"), value: $draft.fatGrams, format: .number)
                        .keyboardType(.decimalPad)
                    TextField(text("Fiber grams", "Gram fiber"), value: $draft.fiberGrams, format: .number)
                        .keyboardType(.decimalPad)
                }

                Section(text("Ingredients", "Ingredienser")) {
                    TextField(text("One ingredient per line", "Én ingrediens per linje"), text: $draft.ingredientsText, axis: .vertical)
                        .lineLimit(8, reservesSpace: true)
                }

                Section(text("Steps", "Fremgangsmåte")) {
                    TextField(text("One step per line", "Ett steg per linje"), text: $draft.stepsText, axis: .vertical)
                        .lineLimit(8, reservesSpace: true)
                }

                Section(text("Tags and source", "Etiketter og kilde")) {
                    TextField(text("Tags separated by comma", "Etiketter separert med komma"), text: $draft.tagsText)
                    TextField(text("Source name", "Kildenavn"), text: $draft.sourceName)
                    TextField(text("Source URL", "Kilde-URL"), text: $draft.sourceURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    TextField(text("Notes", "Notater"), text: $draft.notes, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(text("Cancel", "Avbryt"), action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(text("Save", "Lagre"), action: save)
                        .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.caloriesPerServing > 0
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private struct PlanRecipeSheet: View {
    let recipe: Recipe
    let language: AppLanguage
    let defaultServings: Int
    let autoAddIngredientsToShoppingList: Bool
    let enabledStores: [GroceryStore]
    let storePrices: [StorePrice]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var date = Date()
    @State private var mealSlot: MealSlot = .dinner
    @State private var servings: Int

    init(recipe: Recipe, language: AppLanguage, defaultServings: Int, autoAddIngredientsToShoppingList: Bool, enabledStores: [GroceryStore], storePrices: [StorePrice]) {
        self.recipe = recipe
        self.language = language
        self.defaultServings = defaultServings
        self.autoAddIngredientsToShoppingList = autoAddIngredientsToShoppingList
        self.enabledStores = enabledStores
        self.storePrices = storePrices
        _servings = State(initialValue: min(max(defaultServings, 1), 24))
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(text("Date", "Dato"), selection: $date, displayedComponents: .date)
                Picker(text("Meal", "Måltid"), selection: $mealSlot) {
                    ForEach(MealSlot.allCases) { slot in
                        Text(slot.title(language: language)).tag(slot)
                    }
                }
                Stepper("\(servings) " + text("servings", "porsjoner"), value: $servings, in: 1...24)
                Toggle(text("Add ingredients to shopping list", "Legg ingredienser til handlelisten"), isOn: .constant(autoAddIngredientsToShoppingList))
                    .disabled(true)
            }
            .navigationTitle(recipe.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(text("Cancel", "Avbryt")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(text("Plan", "Planlegg"), action: save)
                }
            }
        }
    }

    private func save() {
        modelContext.insert(MealPlanEntry(date: date, mealSlot: mealSlot, recipeTitle: recipe.title, servings: servings))
        if autoAddIngredientsToShoppingList {
            addIngredientsToShoppingList()
        }
        dismiss()
    }

    private func addIngredientsToShoppingList() {
        for ingredient in recipe.ingredients where !ingredient.isEmpty {
            let option = StorePriceMatcher.cheapestOption(for: ingredient, prices: storePrices, enabledStores: enabledStores)
            modelContext.insert(ShoppingListItem(name: ingredient, quantity: "1", unit: text("item", "vare"), targetStore: option?.store ?? enabledStores.first ?? .rema1000, estimatedUnitPrice: option?.price ?? 0, sourceRecipeTitle: recipe.title, category: .other, priority: .normal, neededBy: date))
        }
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private struct RecipeRow: View {
    let recipe: Recipe
    let language: AppLanguage
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(recipe.title)
                    .font(.headline)
                Spacer()
                if recipe.isFavorite {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                }
            }

            Text("\(recipe.servings) " + text("servings", "porsjoner") + " · \(recipe.totalMinutes) min · " + recipe.estimatedCost.formattedCurrency(code: currencyCode))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(recipe.course.title(language: language) + " · " + recipe.difficulty.title(language: language) + cuisineText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Label("\(recipe.caloriesPerServing) kcal · \(recipe.proteinGrams.formatted()) g " + text("protein", "protein"), systemImage: "flame")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !recipe.tags.isEmpty {
                Text(recipe.tags.prefix(4).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private var cuisineText: String {
        recipe.cuisine.isEmpty ? "" : " · \(recipe.cuisine)"
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private struct RecipeMetricTile: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct FlowText: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: "tag")
            }
        }
    }
}

private struct RecipeDraft {
    var title = ""
    var summary = ""
    var servings = 2
    var estimatedCost = 0.0
    var course: RecipeCourse = .dinner
    var difficulty: RecipeDifficulty = .easy
    var cuisine = ""
    var prepMinutes = 10
    var cookMinutes = 20
    var caloriesPerServing = 0
    var proteinGrams = 0.0
    var carbohydrateGrams = 0.0
    var fatGrams = 0.0
    var fiberGrams = 0.0
    var ingredientsText = ""
    var stepsText = ""
    var tagsText = ""
    var sourceName = ""
    var sourceURL = ""
    var notes = ""

    init() {}

    init(recipe: Recipe) {
        title = recipe.title
        summary = recipe.summary
        servings = recipe.servings
        estimatedCost = recipe.estimatedCost
        course = recipe.course
        difficulty = recipe.difficulty
        cuisine = recipe.cuisine
        prepMinutes = recipe.prepMinutes
        cookMinutes = recipe.cookMinutes
        caloriesPerServing = recipe.caloriesPerServing
        proteinGrams = recipe.proteinGrams
        carbohydrateGrams = recipe.carbohydrateGrams
        fatGrams = recipe.fatGrams
        fiberGrams = recipe.fiberGrams
        ingredientsText = recipe.ingredients.joined(separator: "\n")
        stepsText = recipe.steps.joined(separator: "\n")
        tagsText = recipe.tags.joined(separator: ", ")
        sourceName = recipe.sourceName
        sourceURL = recipe.sourceURL
        notes = recipe.notes
    }

    func makeRecipe() -> Recipe {
        Recipe(title: title, summary: summary, servings: servings, ingredients: splitLines(ingredientsText), steps: splitLines(stepsText), estimatedCost: estimatedCost, course: course, difficulty: difficulty, cuisine: cuisine, tags: splitTags(tagsText), prepMinutes: prepMinutes, cookMinutes: cookMinutes, caloriesPerServing: caloriesPerServing, proteinGrams: proteinGrams, carbohydrateGrams: carbohydrateGrams, fatGrams: fatGrams, fiberGrams: fiberGrams, sourceName: sourceName, sourceURL: sourceURL, notes: notes)
    }

    func apply(to recipe: Recipe) {
        recipe.title = title
        recipe.summary = summary
        recipe.servings = servings
        recipe.ingredients = splitLines(ingredientsText)
        recipe.steps = splitLines(stepsText)
        recipe.estimatedCost = estimatedCost
        recipe.course = course
        recipe.difficulty = difficulty
        recipe.cuisine = cuisine
        recipe.tags = splitTags(tagsText)
        recipe.prepMinutes = prepMinutes
        recipe.cookMinutes = cookMinutes
        recipe.caloriesPerServing = caloriesPerServing
        recipe.proteinGrams = proteinGrams
        recipe.carbohydrateGrams = carbohydrateGrams
        recipe.fatGrams = fatGrams
        recipe.fiberGrams = fiberGrams
        recipe.sourceName = sourceName
        recipe.sourceURL = sourceURL
        recipe.notes = notes
    }

    private func splitLines(_ value: String) -> [String] {
        value.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func splitTags(_ value: String) -> [String] {
        value.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

enum RecipeFilter: String, CaseIterable, Identifiable {
    case all
    case favorites
    case quick
    case cheap
    case highProtein
    case notCookedRecently

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.all, .english): "All"
        case (.all, .norwegian): "Alle"
        case (.favorites, .english): "Favorites"
        case (.favorites, .norwegian): "Favoritter"
        case (.quick, .english): "Quick"
        case (.quick, .norwegian): "Rask"
        case (.cheap, .english): "Budget"
        case (.cheap, .norwegian): "Budsjett"
        case (.highProtein, .english): "High protein"
        case (.highProtein, .norwegian): "Proteinrik"
        case (.notCookedRecently, .english): "Not cooked recently"
        case (.notCookedRecently, .norwegian): "Ikke laget nylig"
        }
    }
}

enum RecipeSortMode: String, CaseIterable, Identifiable {
    case name
    case costLowToHigh
    case quickest
    case newest
    case mostCooked

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.name, .english): "Name"
        case (.name, .norwegian): "Navn"
        case (.costLowToHigh, .english): "Lowest cost"
        case (.costLowToHigh, .norwegian): "Lavest kostnad"
        case (.quickest, .english): "Quickest"
        case (.quickest, .norwegian): "Raskest"
        case (.newest, .english): "Newest"
        case (.newest, .norwegian): "Nyeste"
        case (.mostCooked, .english): "Most cooked"
        case (.mostCooked, .norwegian): "Mest laget"
        }
    }
}
