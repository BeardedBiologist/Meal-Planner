import SwiftData
import SwiftUI

struct ShoppingListView: View {
    let language: AppLanguage
    let currencyCode: String
    let enabledStores: [GroceryStore]
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ShoppingListItem.createdAt) private var items: [ShoppingListItem]
    @Query(sort: \StorePrice.updatedAt, order: .reverse) private var storePrices: [StorePrice]
    @State private var showAddItem = false
    @State private var viewMode: ShoppingListViewMode = .byStore
    @State private var sortMode: ShoppingSortMode = .storeThenCategory
    @State private var showCheckedItems = true
    @State private var selectedStoreFilter: GroceryStore?

    private var enabledStoreRawValues: Set<String> {
        Set(enabledStores.map(\.rawValue))
    }

    private var visibleItems: [ShoppingListItem] {
        let filtered = items.filter { item in
            let matchesChecked = showCheckedItems || !item.isChecked
            let matchesStore = selectedStoreFilter == nil || item.targetStoreRawValue == selectedStoreFilter?.rawValue
            return matchesChecked && matchesStore && enabledStoreRawValues.contains(item.targetStoreRawValue)
        }

        return filtered.sorted { lhs, rhs in
            switch sortMode {
            case .storeThenCategory:
                if lhs.targetStore.displayName != rhs.targetStore.displayName {
                    return lhs.targetStore.displayName < rhs.targetStore.displayName
                }
                if lhs.category.title(language: language) != rhs.category.title(language: language) {
                    return lhs.category.title(language: language) < rhs.category.title(language: language)
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .name:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .priceHighToLow:
                return lhs.estimatedUnitPrice > rhs.estimatedUnitPrice
            case .priority:
                return priorityRank(lhs.priority) > priorityRank(rhs.priority)
            case .newest:
                return lhs.createdAt > rhs.createdAt
            }
        }
    }

    private var openItems: [ShoppingListItem] {
        visibleItems.filter { !$0.isChecked }
    }

    private var total: Double {
        openItems.reduce(0) { $0 + $1.estimatedUnitPrice }
    }

    private var storeTotals: [(store: GroceryStore, items: [ShoppingListItem], total: Double)] {
        enabledStores.map { store in
            let storeItems = visibleItems.filter { $0.targetStoreRawValue == store.rawValue }
            let total = storeItems.filter { !$0.isChecked }.reduce(0) { $0 + $1.estimatedUnitPrice }
            return (store, storeItems, total)
        }
        .filter { !$0.items.isEmpty }
    }

    private var categoryGroups: [(category: ShoppingCategory, items: [ShoppingListItem], total: Double)] {
        ShoppingCategory.allCases.map { category in
            let categoryItems = visibleItems.filter { $0.categoryRawValue == category.rawValue }
            let total = categoryItems.filter { !$0.isChecked }.reduce(0) { $0 + $1.estimatedUnitPrice }
            return (category, categoryItems, total)
        }
        .filter { !$0.items.isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                controlsSection
                contentSection
            }
            .navigationTitle(text("Shopping List", "Handleliste"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        assignOpenItemsToCheapestStores()
                    } label: {
                        Label(text("Optimize", "Optimaliser"), systemImage: "wand.and.stars")
                    }
                    .disabled(openItems.isEmpty)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddItem = true
                    } label: {
                        Label(text("Add Item", "Legg til"), systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddItem) {
                AddShoppingItemView(language: language, currencyCode: currencyCode, enabledStores: enabledStores, storePrices: storePrices)
            }
        }
    }

    private var summarySection: some View {
        Section {
            HStack(spacing: 12) {
                ShoppingMetricTile(title: text("Open total", "Åpen total"), value: total.formattedCurrency(code: currencyCode), icon: "creditcard")
                ShoppingMetricTile(title: text("Items", "Varer"), value: "\(openItems.count)", icon: "cart")
            }

            if storeTotals.isEmpty {
                Text(text("No tracked shopping items yet.", "Ingen handlevarer for valgte butikker ennå."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(storeTotals, id: \.store.id) { group in
                    HStack {
                        Label(group.store.displayName, systemImage: "storefront")
                        Spacer()
                        Text(group.total.formattedCurrency(code: currencyCode))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var controlsSection: some View {
        Section(text("View options", "Visningsvalg")) {
            Picker(text("View", "Visning"), selection: $viewMode) {
                ForEach(ShoppingListViewMode.allCases) { mode in
                    Text(mode.title(language: language)).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Picker(text("Sort", "Sorter"), selection: $sortMode) {
                ForEach(ShoppingSortMode.allCases) { mode in
                    Text(mode.title(language: language)).tag(mode)
                }
            }

            Picker(text("Store filter", "Butikkfilter"), selection: $selectedStoreFilter) {
                Text(text("All tracked stores", "Alle valgte butikker")).tag(nil as GroceryStore?)
                ForEach(enabledStores) { store in
                    Text(store.displayName).tag(store as GroceryStore?)
                }
            }

            Toggle(text("Show checked items", "Vis avkryssede varer"), isOn: $showCheckedItems)
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        if visibleItems.isEmpty {
            Section {
                ContentUnavailableView(text("Shopping list is empty", "Handlelisten er tom"), systemImage: "cart", description: Text(text("Plan meals, scan receipts, or add grocery items manually.", "Planlegg måltider, skann kvitteringer eller legg inn varer manuelt.")))
            }
        } else {
            switch viewMode {
            case .byStore:
                ForEach(storeTotals, id: \.store.id) { group in
                    Section("\(group.store.displayName) · \(group.total.formattedCurrency(code: currencyCode))") {
                        ForEach(group.items) { item in
                            ShoppingItemRow(item: item, language: language, currencyCode: currencyCode, cheapestOption: cheapestOption(for: item))
                        }
                        .onDelete { offsets in
                            deleteItems(offsets: offsets, from: group.items)
                        }
                    }
                }
            case .byCategory:
                ForEach(categoryGroups, id: \.category.id) { group in
                    Section("\(group.category.title(language: language)) · \(group.total.formattedCurrency(code: currencyCode))") {
                        ForEach(group.items) { item in
                            ShoppingItemRow(item: item, language: language, currencyCode: currencyCode, cheapestOption: cheapestOption(for: item))
                        }
                        .onDelete { offsets in
                            deleteItems(offsets: offsets, from: group.items)
                        }
                    }
                }
            case .flatList:
                Section(text("All items", "Alle varer")) {
                    ForEach(visibleItems) { item in
                        ShoppingItemRow(item: item, language: language, currencyCode: currencyCode, cheapestOption: cheapestOption(for: item))
                    }
                    .onDelete { offsets in
                        deleteItems(offsets: offsets, from: visibleItems)
                    }
                }
            }
        }
    }

    private func assignOpenItemsToCheapestStores() {
        for item in items where !item.isChecked {
            guard let option = cheapestOption(for: item) else { continue }
            item.targetStoreRawValue = option.store.rawValue
            item.estimatedUnitPrice = option.price
        }
    }

    private func cheapestOption(for item: ShoppingListItem) -> StorePriceOption? {
        StorePriceMatcher.cheapestOption(for: item.name, prices: storePrices, enabledStores: enabledStores)
    }

    private func deleteItems(offsets: IndexSet, from source: [ShoppingListItem]) {
        for index in offsets {
            modelContext.delete(source[index])
        }
    }

    private func priorityRank(_ priority: ShoppingPriority) -> Int {
        switch priority {
        case .low: 0
        case .normal: 1
        case .high: 2
        }
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

struct AddShoppingItemView: View {
    let language: AppLanguage
    let currencyCode: String
    let enabledStores: [GroceryStore]
    let storePrices: [StorePrice]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var quantity = "1"
    @State private var unit = "stk"
    @State private var store: GroceryStore
    @State private var estimatedPrice = 0.0
    @State private var category: ShoppingCategory = .other
    @State private var priority: ShoppingPriority = .normal
    @State private var notes = ""
    @State private var useNeededByDate = false
    @State private var neededBy = Date()
    @State private var useCheapestStore = true
    @State private var savePriceToDatabase = true

    private var cheapestOption: StorePriceOption? {
        StorePriceMatcher.cheapestOption(for: name, prices: storePrices, enabledStores: enabledStores)
    }

    init(language: AppLanguage, currencyCode: String, enabledStores: [GroceryStore], storePrices: [StorePrice]) {
        self.language = language
        self.currencyCode = currencyCode
        self.enabledStores = enabledStores
        self.storePrices = storePrices
        _store = State(initialValue: enabledStores.first ?? .rema1000)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(text("Item", "Vare")) {
                    TextField(text("Item", "Vare"), text: $name)
                    HStack {
                        TextField(text("Quantity", "Antall"), text: $quantity)
                        TextField(text("Unit", "Enhet"), text: $unit)
                    }

                    Picker(text("Category", "Kategori"), selection: $category) {
                        ForEach(ShoppingCategory.allCases) { category in
                            Text(category.title(language: language)).tag(category)
                        }
                    }

                    Picker(text("Priority", "Prioritet"), selection: $priority) {
                        ForEach(ShoppingPriority.allCases) { priority in
                            Text(priority.title(language: language)).tag(priority)
                        }
                    }
                }

                Section(text("Store and price", "Butikk og pris")) {
                    Toggle(text("Use cheapest tracked store", "Bruk billigste valgte butikk"), isOn: $useCheapestStore)

                    if let cheapestOption {
                        Label(text("Cheapest average", "Billigste snitt") + ": \(cheapestOption.store.displayName) · \(cheapestOption.price.formattedCurrency(code: currencyCode)) · \(cheapestOption.sampleCount) " + text("prices", "priser"), systemImage: "tag")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(text("No saved price match yet. Scan receipts to improve suggestions.", "Ingen lagret prismatch ennå. Skann kvitteringer for bedre forslag."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Picker(text("Store", "Butikk"), selection: $store) {
                        ForEach(enabledStores) { store in
                            Text(store.displayName).tag(store)
                        }
                    }
                    .disabled(useCheapestStore && cheapestOption != nil)

                    TextField(text("Estimated price", "Estimert pris"), value: $estimatedPrice, format: .number)
                        .keyboardType(.decimalPad)

                    Toggle(text("Save this price for future comparisons", "Lagre denne prisen for fremtidige sammenligninger"), isOn: $savePriceToDatabase)
                }

                Section(text("Planning", "Planlegging")) {
                    Toggle(text("Needed by date", "Trengs innen dato"), isOn: $useNeededByDate)
                    if useNeededByDate {
                        DatePicker(text("Needed by", "Trengs innen"), selection: $neededBy, displayedComponents: .date)
                    }
                    TextField(text("Notes", "Notater"), text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
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
            .onChange(of: name) { _, _ in
                applyCheapestSuggestionIfNeeded()
            }
            .onChange(of: useCheapestStore) { _, _ in
                applyCheapestSuggestionIfNeeded()
            }
        }
    }

    private func applyCheapestSuggestionIfNeeded() {
        guard useCheapestStore, let cheapestOption else { return }
        store = cheapestOption.store
        estimatedPrice = cheapestOption.price
    }

    private func save() {
        applyCheapestSuggestionIfNeeded()
        modelContext.insert(ShoppingListItem(
            name: name,
            quantity: quantity,
            unit: unit,
            targetStore: store,
            estimatedUnitPrice: estimatedPrice,
            category: category,
            priority: priority,
            notes: notes,
            neededBy: useNeededByDate ? neededBy : nil
        ))

        if savePriceToDatabase, estimatedPrice > 0 {
            modelContext.insert(StorePrice(itemName: name, store: store, price: estimatedPrice, quantity: Double(quantity.replacingOccurrences(of: ",", with: ".")) ?? 1, unit: unit, currency: currencyCode, source: "shopping"))
        }

        dismiss()
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private struct ShoppingItemRow: View {
    @Bindable var item: ShoppingListItem
    let language: AppLanguage
    let currencyCode: String
    let cheapestOption: StorePriceOption?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                item.isChecked.toggle()
            } label: {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.name)
                        .font(.headline)
                        .strikethrough(item.isChecked)
                    Spacer()
                    Text(item.estimatedUnitPrice.formattedCurrency(code: currencyCode))
                        .font(.subheadline.weight(.semibold))
                }

                Text("\(item.quantity) \(item.unit) · \(item.targetStore.displayName) · \(item.category.title(language: language))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Label(item.priority.title(language: language), systemImage: priorityIcon)
                    if let neededBy = item.neededBy {
                        Label(neededBy.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let cheapestOption, cheapestOption.store.rawValue != item.targetStoreRawValue {
                    Button {
                        item.targetStoreRawValue = cheapestOption.store.rawValue
                        item.estimatedUnitPrice = cheapestOption.price
                    } label: {
                        Label(text("Move to cheaper average", "Flytt til billigere snitt") + ": \(cheapestOption.store.displayName) · \(cheapestOption.price.formattedCurrency(code: currencyCode))", systemImage: "arrow.triangle.branch")
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }

                if !item.notes.isEmpty {
                    Text(item.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !item.sourceRecipeTitle.isEmpty {
                    Text(item.sourceRecipeTitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var priorityIcon: String {
        switch item.priority {
        case .low: "arrow.down.circle"
        case .normal: "minus.circle"
        case .high: "exclamationmark.circle"
        }
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private struct ShoppingMetricTile: View {
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

enum ShoppingListViewMode: String, CaseIterable, Identifiable {
    case byStore
    case byCategory
    case flatList

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.byStore, .english): "Store"
        case (.byStore, .norwegian): "Butikk"
        case (.byCategory, .english): "Category"
        case (.byCategory, .norwegian): "Kategori"
        case (.flatList, .english): "List"
        case (.flatList, .norwegian): "Liste"
        }
    }
}

enum ShoppingSortMode: String, CaseIterable, Identifiable {
    case storeThenCategory
    case name
    case priceHighToLow
    case priority
    case newest

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.storeThenCategory, .english): "Store, category"
        case (.storeThenCategory, .norwegian): "Butikk, kategori"
        case (.name, .english): "Name"
        case (.name, .norwegian): "Navn"
        case (.priceHighToLow, .english): "Highest price"
        case (.priceHighToLow, .norwegian): "Høyest pris"
        case (.priority, .english): "Priority"
        case (.priority, .norwegian): "Prioritet"
        case (.newest, .english): "Newest"
        case (.newest, .norwegian): "Nyeste"
        }
    }
}

struct StorePriceOption {
    let store: GroceryStore
    let price: Double
    let sampleCount: Int
}

enum StorePriceMatcher {
    static func cheapestOption(for itemName: String, prices: [StorePrice], enabledStores: [GroceryStore]) -> StorePriceOption? {
        averageOptions(for: itemName, prices: prices, enabledStores: enabledStores)
            .min { $0.price < $1.price }
    }

    static func averageOptions(for itemName: String, prices: [StorePrice], enabledStores: [GroceryStore]) -> [StorePriceOption] {
        let normalizedName = normalize(itemName)
        guard !normalizedName.isEmpty else { return [] }
        let enabledStoreRawValues = Set(enabledStores.map(\.rawValue))
        let matchingPrices = prices
            .filter { enabledStoreRawValues.contains($0.storeRawValue) }
            .filter { price in
                let normalizedPriceName = normalize(price.itemName)
                return normalizedPriceName == normalizedName || normalizedPriceName.contains(normalizedName) || normalizedName.contains(normalizedPriceName)
            }

        let groupedByStore = Dictionary(grouping: matchingPrices, by: \.storeRawValue)
        return groupedByStore.compactMap { storeRawValue, prices in
            guard let store = GroceryStore(rawValue: storeRawValue), !prices.isEmpty else { return nil }
            let average = prices.reduce(0) { $0 + $1.price } / Double(prices.count)
            return StorePriceOption(store: store, price: average, sampleCount: prices.count)
        }
        .sorted { $0.price < $1.price }
    }

    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
