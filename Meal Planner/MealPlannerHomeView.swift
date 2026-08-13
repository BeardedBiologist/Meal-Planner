import PhotosUI
import SwiftData
import SwiftUI
@preconcurrency import Vision

private enum MainAppTab: String, CaseIterable, Identifiable {
    case overview
    case plan
    case recipes
    case shopping
    case receipts
    case settings

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .overview: "chart.bar"
        case .plan: "calendar"
        case .recipes: "book.closed"
        case .shopping: "cart"
        case .receipts: "doc.text.viewfinder"
        case .settings: "gearshape"
        }
    }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.overview, .english): "Overview"
        case (.overview, .norwegian): "Oversikt"
        case (.plan, .english): "Plan"
        case (.plan, .norwegian): "Plan"
        case (.recipes, .english): "Recipes"
        case (.recipes, .norwegian): "Oppskrifter"
        case (.shopping, .english): "Shopping"
        case (.shopping, .norwegian): "Handle"
        case (.receipts, .english): "Receipts"
        case (.receipts, .norwegian): "Kvittering"
        case (.settings, .english): "Settings"
        case (.settings, .norwegian): "Innstillinger"
        }
    }
}

struct MealPlannerHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRecords: [UserSettings]
    @State private var selectedTab: MainAppTab = .overview

    private var settings: UserSettings? {
        settingsRecords.first
    }

    private var language: AppLanguage {
        settings?.preferredLanguage ?? .english
    }

    private var currencyCode: String {
        settings?.currencyCode ?? AppCurrency.nok.rawValue
    }

    private var enabledStores: [GroceryStore] {
        let stores = settings?.enabledStores ?? GroceryStore.defaultTrackedStores
        return stores.isEmpty ? GroceryStore.defaultTrackedStores : stores
    }

    var body: some View {
        VStack(spacing: 0) {
            selectedTabView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            MainTabBar(selectedTab: $selectedTab, language: language)
        }
        .task {
            ensureSettingsRecord()
        }
    }

    @ViewBuilder
    private var selectedTabView: some View {
        switch selectedTab {
        case .overview:
            DashboardView(language: language, currencyCode: currencyCode, enabledStores: enabledStores)
        case .plan:
            MealPlanView(language: language, settings: settings, enabledStores: enabledStores)
        case .recipes:
            RecipesView(language: language, currencyCode: currencyCode, enabledStores: enabledStores, defaultServings: settings?.householdSize ?? 2, autoAddIngredientsToShoppingList: settings?.autoAddIngredientsToShoppingList ?? true)
        case .shopping:
            ShoppingListView(language: language, currencyCode: currencyCode, enabledStores: enabledStores)
        case .receipts:
            ReceiptScannerView(language: language, currencyCode: currencyCode, enabledStores: enabledStores, recognitionLanguage: settings?.receiptRecognitionLanguage ?? .norwegianAndEnglish)
        case .settings:
            SettingsView(language: language, settings: settings, enabledStores: enabledStores)
        }
    }

    private func ensureSettingsRecord() {
        guard settingsRecords.isEmpty else { return }
        modelContext.insert(UserSettings())
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private struct MainTabBar: View {
    @Binding var selectedTab: MainAppTab
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainAppTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 18, weight: selectedTab == tab ? .semibold : .regular))
                        Text(tab.title(language: language))
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title(language: language))
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 5)
        .padding(.bottom, 7)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

private struct DashboardView: View {
    let language: AppLanguage
    let currencyCode: String
    let enabledStores: [GroceryStore]
    @Query private var recipes: [Recipe]
    @Query private var mealPlans: [MealPlanEntry]
    @Query private var shoppingItems: [ShoppingListItem]
    @Query private var receiptItems: [ReceiptLineItem]

    private var enabledStoreRawValues: Set<String> {
        Set(enabledStores.map(\.rawValue))
    }

    private var trackedShoppingItems: [ShoppingListItem] {
        shoppingItems.filter { enabledStoreRawValues.contains($0.targetStoreRawValue) }
    }

    private var trackedReceiptItems: [ReceiptLineItem] {
        receiptItems.filter { enabledStoreRawValues.contains($0.storeRawValue) }
    }

    private var openShoppingTotal: Double {
        trackedShoppingItems.filter { !$0.isChecked }.reduce(0) { $0 + $1.estimatedUnitPrice }
    }

    private var receiptTotal: Double {
        trackedReceiptItems.reduce(0) { $0 + $1.price }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        MetricTile(title: text("Open list", "Åpen liste"), value: openShoppingTotal.formattedCurrency(code: currencyCode), icon: "cart")
                        MetricTile(title: text("Receipts", "Kvitteringer"), value: receiptTotal.formattedCurrency(code: currencyCode), icon: "receipt")
                    }
                    HStack(spacing: 12) {
                        MetricTile(title: text("Recipes", "Oppskrifter"), value: "\(recipes.count)", icon: "book.closed")
                        MetricTile(title: text("Meals planned", "Måltider planlagt"), value: "\(mealPlans.count)", icon: "calendar")
                    }
                }

                Section(text("Tracked store coverage", "Sporing per butikk")) {
                    ForEach(enabledStores) { store in
                        let count = trackedReceiptItems.filter { $0.storeRawValue == store.rawValue }.count
                        Label("\(store.displayName): \(count) " + text("priced items", "prisede varer"), systemImage: "tag")
                    }
                }

                Section(text("Next steps", "Neste steg")) {
                    Text(text("Add recipes, plan meals, then scan receipts after shopping so the app learns real prices for the stores you track.", "Legg inn oppskrifter, planlegg måltider, og skann kvitteringer etter handling slik at appen lærer faktiske priser for butikkene du følger."))
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

private enum PlanDisplayMode: String, CaseIterable, Identifiable {
    case list
    case week
    case month

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.list, .english): "List"
        case (.list, .norwegian): "Liste"
        case (.week, .english): "Week"
        case (.week, .norwegian): "Uke"
        case (.month, .english): "Month"
        case (.month, .norwegian): "Måned"
        }
    }
}

private struct MealPlanView: View {
    let language: AppLanguage
    let settings: UserSettings?
    let enabledStores: [GroceryStore]
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MealPlanEntry.date) private var mealPlans: [MealPlanEntry]
    @State private var displayMode: PlanDisplayMode = .week
    @State private var visibleDate = Date()
    @State private var addMealDate = Date()
    @State private var showAddMeal = false

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = settings?.weekStartsOnMonday ?? true ? 2 : 1
        return calendar
    }

    private var selectedWeekDays: [Date] {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: visibleDate) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekInterval.start) }
    }

    private var visibleMonthDays: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: visibleDate), let monthGridStart = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start)?.start else { return [] }
        let monthEnd = monthInterval.end
        let trailingWeekEnd = calendar.dateInterval(of: .weekOfYear, for: calendar.date(byAdding: .day, value: -1, to: monthEnd) ?? monthEnd)?.end ?? monthEnd
        let dayCount = calendar.dateComponents([.day], from: monthGridStart, to: trailingWeekEnd).day ?? 0
        return (0..<dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: monthGridStart) }
    }

    private var visibleTitle: String {
        switch displayMode {
        case .list:
            return text("All planned meals", "Alle planlagte måltider")
        case .week:
            guard let first = selectedWeekDays.first, let last = selectedWeekDays.last else { return "" }
            return "\(first.formatted(.dateTime.day().month(.abbreviated))) - \(last.formatted(.dateTime.day().month(.abbreviated)))"
        case .month:
            return visibleDate.formatted(.dateTime.month(.wide).year())
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker(text("Plan view", "Planvisning"), selection: $displayMode) {
                    ForEach(PlanDisplayMode.allCases) { mode in
                        Text(mode.title(language: language)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])

                planHeader

                Group {
                    switch displayMode {
                    case .list:
                        mealList
                    case .week:
                        weekView
                    case .month:
                        monthView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(text("Meal Plan", "Måltidsplan"))
            .toolbar {
                Button {
                    addMealDate = visibleDate
                    showAddMeal = true
                } label: {
                    Label(text("Add Meal", "Legg til"), systemImage: "plus")
                }
            }
            .sheet(isPresented: $showAddMeal) {
                AddMealPlanView(
                    language: language,
                    initialDate: addMealDate,
                    defaultServings: settings?.householdSize ?? 2,
                    shouldAddIngredientsToShoppingList: settings?.autoAddIngredientsToShoppingList ?? true,
                    enabledStores: enabledStores
                )
            }
        }
    }

    private var planHeader: some View {
        HStack(spacing: 12) {
            Button {
                moveVisibleDate(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)

            VStack(spacing: 3) {
                Text(visibleTitle)
                    .font(.headline)
                Text(planSummary(for: displayedMealPlans))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Button {
                visibleDate = Date()
            } label: {
                Text(text("Today", "I dag"))
            }
            .buttonStyle(.bordered)

            Button {
                moveVisibleDate(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    private var mealList: some View {
        List {
            if mealPlans.isEmpty {
                ContentUnavailableView(text("No meals planned", "Ingen måltider planlagt"), systemImage: "calendar.badge.plus", description: Text(text("Add meals for a week or month and generate your shopping list from recipes.", "Legg inn måltider for en uke eller måned og lag handlelisten fra oppskriftene.")))
            } else {
                ForEach(groupedPlansByDay(from: mealPlans), id: \.day) { group in
                    Section(group.day.formatted(date: .abbreviated, time: .omitted)) {
                        ForEach(group.plans) { plan in
                            MealPlanRow(plan: plan, language: language)
                        }
                        .onDelete { offsets in
                            deleteMealPlans(offsets: offsets, from: group.plans)
                        }
                    }
                }
            }
        }
    }

    private var weekView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(selectedWeekDays, id: \.self) { day in
                    DayPlanCard(
                        day: day,
                        plans: plans(on: day),
                        language: language,
                        isCurrentMonth: true,
                        addAction: {
                            addMealDate = day
                            showAddMeal = true
                        }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private var monthView: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(visibleMonthDays, id: \.self) { day in
                    MonthDayCell(
                        day: day,
                        plans: plans(on: day),
                        language: language,
                        isCurrentMonth: calendar.isDate(day, equalTo: visibleDate, toGranularity: .month),
                        addAction: {
                            visibleDate = day
                            addMealDate = day
                            showAddMeal = true
                        }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }


    private var displayedMealPlans: [MealPlanEntry] {
        switch displayMode {
        case .list:
            return mealPlans
        case .week:
            return mealPlans.filter { plan in
                selectedWeekDays.contains { calendar.isDate($0, inSameDayAs: plan.date) }
            }
        case .month:
            return mealPlans.filter { calendar.isDate($0.date, equalTo: visibleDate, toGranularity: .month) }
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let firstIndex = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[firstIndex...] + symbols[..<firstIndex])
    }

    private func plans(on day: Date) -> [MealPlanEntry] {
        mealPlans
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { lhs, rhs in
                mealSlotSortIndex(lhs.mealSlot) < mealSlotSortIndex(rhs.mealSlot)
            }
    }

    private func groupedPlansByDay(from plans: [MealPlanEntry]) -> [(day: Date, plans: [MealPlanEntry])] {
        let grouped = Dictionary(grouping: plans) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted().map { day in
            (day, grouped[day]?.sorted { mealSlotSortIndex($0.mealSlot) < mealSlotSortIndex($1.mealSlot) } ?? [])
        }
    }

    private func mealSlotSortIndex(_ slot: MealSlot) -> Int {
        MealSlot.allCases.firstIndex(of: slot) ?? 0
    }

    private func moveVisibleDate(by value: Int) {
        let component: Calendar.Component
        switch displayMode {
        case .list, .week:
            component = .weekOfYear
        case .month:
            component = .month
        }

        visibleDate = calendar.date(byAdding: component, value: value, to: visibleDate) ?? visibleDate
    }

    private func deleteMealPlans(offsets: IndexSet, from source: [MealPlanEntry]) {
        for index in offsets {
            modelContext.delete(source[index])
        }
    }

    private func planSummary(for plans: [MealPlanEntry]) -> String {
        let servings = plans.reduce(0) { $0 + $1.servings }
        return "\(plans.count) " + text("meals", "måltider") + " · \(servings) " + text("servings", "porsjoner")
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private struct MealPlanRow: View {
    let plan: MealPlanEntry
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(plan.recipeTitle)
                .font(.headline)
            Text("\(plan.mealSlot.title(language: language)) · \(plan.servings) " + text("servings", "porsjoner"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private struct DayPlanCard: View {
    let day: Date
    let plans: [MealPlanEntry]
    let language: AppLanguage
    let isCurrentMonth: Bool
    let addAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.formatted(.dateTime.weekday(.wide)))
                        .font(.headline)
                    Text(day.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: addAction) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
            }

            if plans.isEmpty {
                Text(text("No meals planned", "Ingen måltider planlagt"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(plans) { plan in
                    MealPlanRow(plan: plan, language: language)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private struct MonthDayCell: View {
    let day: Date
    let plans: [MealPlanEntry]
    let language: AppLanguage
    let isCurrentMonth: Bool
    let addAction: () -> Void

    var body: some View {
        Button(action: addAction) {
            VStack(alignment: .leading, spacing: 5) {
                Text(day.formatted(.dateTime.day()))
                    .font(.caption.bold())
                    .foregroundStyle(isCurrentMonth ? .primary : .tertiary)

                if plans.isEmpty {
                    Spacer(minLength: 0)
                } else {
                    ForEach(plans.prefix(3)) { plan in
                        Text(plan.mealSlot.title(language: language))
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                    }

                    if plans.count > 3 {
                        Text("+\(plans.count - 3)")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(minHeight: 82, alignment: .topLeading)
            .padding(6)
            .background(Color(.secondarySystemGroupedBackground).opacity(isCurrentMonth ? 1 : 0.5), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct AddMealPlanView: View {
    let language: AppLanguage
    let shouldAddIngredientsToShoppingList: Bool
    let enabledStores: [GroceryStore]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.title) private var recipes: [Recipe]
    @Query(sort: \StorePrice.updatedAt, order: .reverse) private var storePrices: [StorePrice]
    @State private var date: Date
    @State private var mealSlot: MealSlot = .dinner
    @State private var recipeTitle = ""
    @State private var servings: Int

    init(language: AppLanguage, initialDate: Date = Date(), defaultServings: Int = 2, shouldAddIngredientsToShoppingList: Bool = true, enabledStores: [GroceryStore] = GroceryStore.defaultTrackedStores) {
        self.language = language
        self.shouldAddIngredientsToShoppingList = shouldAddIngredientsToShoppingList
        self.enabledStores = enabledStores
        _date = State(initialValue: initialDate)
        _servings = State(initialValue: min(max(defaultServings, 1), 12))
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
        if shouldAddIngredientsToShoppingList, let recipe = recipes.first(where: { $0.title == recipeTitle }) {
            addIngredientsToShoppingList(from: recipe)
        }
        dismiss()
    }

    private func addIngredientsToShoppingList(from recipe: Recipe) {
        for ingredient in recipe.ingredients where !ingredient.isEmpty {
            let cheapestOption = StorePriceMatcher.cheapestOption(for: ingredient, prices: storePrices, enabledStores: enabledStores)
            modelContext.insert(ShoppingListItem(
                name: ingredient,
                quantity: "1",
                unit: text("item", "vare"),
                targetStore: cheapestOption?.store ?? enabledStores.first ?? .rema1000,
                estimatedUnitPrice: cheapestOption?.price ?? 0,
                sourceRecipeTitle: recipe.title,
                category: .other,
                priority: .normal
            ))
        }
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private struct ReceiptScannerView: View {
    let language: AppLanguage
    let currencyCode: String
    let enabledStores: [GroceryStore]
    let recognitionLanguage: ReceiptRecognitionLanguage
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ReceiptLineItem.purchasedAt, order: .reverse) private var receiptItems: [ReceiptLineItem]
    @State private var selectedStore: GroceryStore
    @State private var selectedPhoto: PhotosPickerItem?

    init(language: AppLanguage, currencyCode: String, enabledStores: [GroceryStore], recognitionLanguage: ReceiptRecognitionLanguage) {
        self.language = language
        self.currencyCode = currencyCode
        self.enabledStores = enabledStores
        self.recognitionLanguage = recognitionLanguage
        _selectedStore = State(initialValue: enabledStores.first ?? .rema1000)
    }
    @State private var recognizedLines: [ParsedReceiptLine] = []
    @State private var isScanning = false
    @State private var scanError: String?

    private var trackedReceiptItems: [ReceiptLineItem] {
        let enabledStoreRawValues = Set(enabledStores.map(\.rawValue))
        return receiptItems.filter { enabledStoreRawValues.contains($0.storeRawValue) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section(text("Scan receipt", "Skann kvittering")) {
                    Picker(text("Store", "Butikk"), selection: $selectedStore) {
                        ForEach(enabledStores) { store in
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
                                Text(line.price.formattedCurrency(code: currencyCode))
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
                    if trackedReceiptItems.isEmpty {
                        Text(text("No receipt prices saved yet for tracked stores.", "Ingen kvitteringspriser lagret ennå for valgte butikker."))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(trackedReceiptItems) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.itemName)
                                        .font(.headline)
                                    Text("\(item.store.displayName) · \(item.purchasedAt.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(item.price.formattedCurrency(code: currencyCode))
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

            let lines = try await ReceiptTextRecognizer.recognizeText(in: cgImage, language: recognitionLanguage)
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

private struct SettingsView: View {
    let language: AppLanguage
    let settings: UserSettings?
    let enabledStores: [GroceryStore]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Group {
                if let settings {
                    SettingsFormView(language: language, settings: settings, enabledStores: enabledStores)
                } else {
                    VStack(spacing: 16) {
                        ContentUnavailableView(text("Settings unavailable", "Innstillinger er utilgjengelige"), systemImage: "gearshape", description: Text(text("Create a local settings record to continue.", "Opprett lokale innstillinger for å fortsette.")))
                        Button(text("Create Settings", "Opprett innstillinger")) {
                            modelContext.insert(UserSettings())
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle(text("Settings", "Innstillinger"))
        }
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private struct SettingsFormView: View {
    let language: AppLanguage
    @Bindable var settings: UserSettings
    let enabledStores: [GroceryStore]
    private let authManager = AuthenticationManager.shared
    @Environment(\.modelContext) private var modelContext
    @Query private var shoppingItems: [ShoppingListItem]
    @Query private var receiptItems: [ReceiptLineItem]
    @Query private var storePrices: [StorePrice]

    private var storesByParent: [(parent: String, stores: [GroceryStore])] {
        let grouped = Dictionary(grouping: GroceryStore.allCases, by: \.parentCompany)
        return grouped.keys.sorted().map { parent in
            (parent, grouped[parent]?.sorted { $0.displayName < $1.displayName } ?? [])
        }
    }

    var body: some View {
        Form {
            Section(text("User", "Bruker")) {
                TextField(text("Name", "Navn"), text: $settings.displayName)
                    .textContentType(.name)
                TextField(text("Email", "E-post"), text: $settings.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
            }

            Section(text("Preferences", "Preferanser")) {
                Picker(text("Language", "Språk"), selection: $settings.preferredLanguageRawValue) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }

                TextField(text("Weekly grocery budget", "Ukentlig matbudsjett"), value: $settings.weeklyBudget, format: .number)
                    .keyboardType(.decimalPad)

                Picker(text("Currency", "Valuta"), selection: $settings.currencyCode) {
                    ForEach(AppCurrency.allCases) { currency in
                        Text(currency.title).tag(currency.rawValue)
                    }
                }
            }

            Section(text("Planning", "Planlegging")) {
                Stepper("\(settings.householdSize) " + text("people", "personer"), value: $settings.householdSize, in: 1...12)
                Picker(text("Planning range", "Planleggingsperiode"), selection: $settings.planningHorizonDays) {
                    Text(text("1 week", "1 uke")).tag(7)
                    Text(text("2 weeks", "2 uker")).tag(14)
                    Text(text("1 month", "1 måned")).tag(30)
                }
                Toggle(text("Week starts on Monday", "Uken starter på mandag"), isOn: $settings.weekStartsOnMonday)
                Toggle(text("Add recipe ingredients to shopping list", "Legg oppskriftsingredienser til handlelisten"), isOn: $settings.autoAddIngredientsToShoppingList)
            }

            Section(text("Savings", "Sparing")) {
                Toggle(text("Prefer cheapest tracked store", "Foretrekk billigste valgte butikk"), isOn: $settings.preferCheapestTrackedStore)
                Toggle(text("Show budget warnings", "Vis budsjettvarsler"), isOn: $settings.showBudgetWarnings)
                Toggle(text("Prices include tax", "Priser inkluderer mva"), isOn: $settings.includeTaxInPrices)
            }

            Section(text("Diet", "Kosthold")) {
                ForEach(DietaryPreference.allCases) { preference in
                    Toggle(preference.title(language: language), isOn: dietaryPreferenceBinding(for: preference))
                }
            }

            Section(text("Receipts", "Kvitteringer")) {
                Picker(text("OCR language", "OCR-språk"), selection: $settings.receiptRecognitionLanguageRawValue) {
                    ForEach(ReceiptRecognitionLanguage.allCases) { recognitionLanguage in
                        Text(recognitionLanguage.title(language: language)).tag(recognitionLanguage.rawValue)
                    }
                }
            }

            Section(text("Reminders", "Påminnelser")) {
                Toggle(text("Receipt scanning reminders", "Påminnelse om kvitteringsskann"), isOn: $settings.receiptRemindersEnabled)
                Toggle(text("Shopping list reminders", "Påminnelse om handleliste"), isOn: $settings.shoppingRemindersEnabled)
            }

            Section {
                HStack {
                    Label("\(enabledStores.count) " + text("tracked stores", "valgte butikker"), systemImage: "storefront")
                    Spacer()
                    Menu {
                        Button(text("Use my defaults", "Bruk mine standardvalg")) {
                            settings.enabledStoreRawValues = GroceryStore.defaultTrackedStores.map(\.rawValue)
                        }
                        Button(text("Track all", "Følg alle")) {
                            settings.enabledStoreRawValues = GroceryStore.allCases.map(\.rawValue)
                        }
                        Button(role: .destructive) {
                            settings.enabledStoreRawValues = []
                        } label: {
                            Text(text("Clear all", "Fjern alle"))
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            } header: {
                Text(text("Supermarkets", "Dagligvarebutikker"))
            } footer: {
                Text(text("Overview totals, receipt price coverage, and shopping store choices use only enabled stores.", "Oversiktstotaler, kvitteringspriser og butikkvalg i handlelisten bruker bare valgte butikker."))
            }

            ForEach(storesByParent, id: \.parent) { group in
                Section(group.parent) {
                    ForEach(group.stores) { store in
                        Toggle(isOn: storeBinding(for: store)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.displayName)
                                Text(store.storeType)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    clearCheckedShoppingItems()
                } label: {
                    Label(text("Clear checked shopping items", "Fjern avkryssede handlevarer"), systemImage: "checkmark.circle")
                }

                Button(role: .destructive) {
                    clearReceiptHistory()
                } label: {
                    Label(text("Clear receipt history", "Fjern kvitteringshistorikk"), systemImage: "receipt")
                }
            } header: {
                Text(text("Data", "Data"))
            } footer: {
                Text(text("These actions only remove local app data on this device.", "Disse handlingene fjerner bare lokale appdata på denne enheten."))
            }

            Section(text("Account", "Konto")) {
                Button(role: .destructive) {
                    authManager.signOut()
                } label: {
                    Label(text("Log Out", "Logg ut"), systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
    }

    private func storeBinding(for store: GroceryStore) -> Binding<Bool> {
        Binding {
            settings.isStoreEnabled(store)
        } set: { isEnabled in
            settings.setStore(store, isEnabled: isEnabled)
        }
    }

    private func dietaryPreferenceBinding(for preference: DietaryPreference) -> Binding<Bool> {
        Binding {
            settings.hasDietaryPreference(preference)
        } set: { isEnabled in
            settings.setDietaryPreference(preference, isEnabled: isEnabled)
        }
    }

    private func clearCheckedShoppingItems() {
        for item in shoppingItems where item.isChecked {
            modelContext.delete(item)
        }
    }

    private func clearReceiptHistory() {
        for item in receiptItems {
            modelContext.delete(item)
        }

        for price in storePrices {
            modelContext.delete(price)
        }
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
    static func recognizeText(in image: CGImage, language: ReceiptRecognitionLanguage) async throws -> [String] {
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
            request.recognitionLanguages = language.visionLanguageCodes
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

private extension ReceiptRecognitionLanguage {
    var visionLanguageCodes: [String] {
        switch self {
        case .norwegianAndEnglish:
            ["nb-NO", "en-US"]
        case .norwegian:
            ["nb-NO"]
        case .english:
            ["en-US"]
        }
    }
}

extension Double {
    func formattedCurrency(code: String) -> String {
        formatted(.currency(code: code))
    }
}
