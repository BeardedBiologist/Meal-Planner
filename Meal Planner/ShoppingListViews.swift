import SwiftData
import SwiftUI

struct ShoppingHomeView: View {
    let language: AppLanguage
    let currencyCode: String
    let enabledStores: [GroceryStore]
    @State private var selectedView: ShoppingHomeMode = .list

    var body: some View {
        VStack(spacing: 0) {
            Picker(text("Shopping section", "Handlevisning"), selection: $selectedView) {
                ForEach(ShoppingHomeMode.allCases) { mode in
                    Text(mode.title(language: language)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])
            .background(Color(.systemGroupedBackground))

            switch selectedView {
            case .list:
                ShoppingListView(language: language, currencyCode: currencyCode, enabledStores: enabledStores)
            case .prices:
                PriceTrackerView(language: language, currencyCode: currencyCode, enabledStores: enabledStores)
            }
        }
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private enum ShoppingHomeMode: String, CaseIterable, Identifiable {
    case list
    case prices

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.list, .english): "List"
        case (.list, .norwegian): "Liste"
        case (.prices, .english): "Prices"
        case (.prices, .norwegian): "Priser"
        }
    }
}

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
    @State private var editingItem: ShoppingListItem?

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
                    Menu {
                        Button {
                            assignOpenItemsToCheapestStores()
                        } label: {
                            Label(text("Optimize stores", "Optimaliser butikker"), systemImage: "wand.and.stars")
                        }
                        .disabled(openItems.isEmpty)

                        Button {
                            saveShoppingPricesToDatabase()
                        } label: {
                            Label(text("Sync prices", "Synk priser"), systemImage: "tag")
                        }
                        .disabled(!visibleItems.contains { $0.estimatedUnitPrice > 0 })
                    } label: {
                        Label(text("Tools", "Verktøy"), systemImage: "ellipsis.circle")
                    }
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
            .sheet(item: $editingItem) { item in
                EditShoppingItemView(item: item, language: language, currencyCode: currencyCode, enabledStores: enabledStores, storePrices: storePrices)
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
                                .contentShape(Rectangle())
                                .onTapGesture { editingItem = item }
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
                                .contentShape(Rectangle())
                                .onTapGesture { editingItem = item }
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
                            .contentShape(Rectangle())
                            .onTapGesture { editingItem = item }
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

    private func saveShoppingPricesToDatabase() {
        for item in visibleItems where item.estimatedUnitPrice > 0 {
            upsertStorePrice(
                itemName: item.name,
                store: item.targetStore,
                price: item.estimatedUnitPrice,
                quantity: Double(item.quantity.replacingOccurrences(of: ",", with: ".")) ?? 1,
                unit: item.unit,
                source: "shopping"
            )
        }
    }

    private func upsertStorePrice(itemName: String, store: GroceryStore, price: Double, quantity: Double, unit: String, source: String) {
        if let existing = storePrices.first(where: {
            StorePriceMatcher.normalize($0.itemName) == StorePriceMatcher.normalize(itemName) && $0.storeRawValue == store.rawValue
        }) {
            existing.itemName = itemName
            existing.price = price
            existing.quantity = quantity
            existing.unit = unit
            existing.currency = currencyCode
            existing.source = source
            existing.updatedAt = .now
        } else {
            modelContext.insert(StorePrice(itemName: itemName, store: store, price: price, quantity: quantity, unit: unit, currency: currencyCode, source: source))
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
            upsertStorePrice()
        }

        dismiss()
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }

    private func upsertStorePrice() {
        let normalizedName = StorePriceMatcher.normalize(name)
        if let existing = storePrices.first(where: {
            StorePriceMatcher.normalize($0.itemName) == normalizedName && $0.storeRawValue == store.rawValue
        }) {
            existing.itemName = name
            existing.price = estimatedPrice
            existing.quantity = Double(quantity.replacingOccurrences(of: ",", with: ".")) ?? 1
            existing.unit = unit
            existing.currency = currencyCode
            existing.source = "shopping"
            existing.updatedAt = .now
        } else {
            modelContext.insert(StorePrice(itemName: name, store: store, price: estimatedPrice, quantity: Double(quantity.replacingOccurrences(of: ",", with: ".")) ?? 1, unit: unit, currency: currencyCode, source: "shopping"))
        }
    }
}

private struct EditShoppingItemView: View {
    @Bindable var item: ShoppingListItem
    let language: AppLanguage
    let currencyCode: String
    let enabledStores: [GroceryStore]
    let storePrices: [StorePrice]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var store: GroceryStore
    @State private var useNeededByDate: Bool
    @State private var neededBy: Date
    @State private var savePriceToDatabase = true

    init(item: ShoppingListItem, language: AppLanguage, currencyCode: String, enabledStores: [GroceryStore], storePrices: [StorePrice]) {
        self.item = item
        self.language = language
        self.currencyCode = currencyCode
        self.enabledStores = enabledStores
        self.storePrices = storePrices
        _store = State(initialValue: item.targetStore)
        _useNeededByDate = State(initialValue: item.neededBy != nil)
        _neededBy = State(initialValue: item.neededBy ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(text("Item", "Vare")) {
                    TextField(text("Item", "Vare"), text: $item.name)
                    HStack {
                        TextField(text("Quantity", "Antall"), text: $item.quantity)
                        TextField(text("Unit", "Enhet"), text: $item.unit)
                    }
                    Picker(text("Category", "Kategori"), selection: $item.categoryRawValue) {
                        ForEach(ShoppingCategory.allCases) { category in
                            Text(category.title(language: language)).tag(category.rawValue)
                        }
                    }
                    Picker(text("Priority", "Prioritet"), selection: $item.priorityRawValue) {
                        ForEach(ShoppingPriority.allCases) { priority in
                            Text(priority.title(language: language)).tag(priority.rawValue)
                        }
                    }
                }

                Section(text("Store and price", "Butikk og pris")) {
                    Picker(text("Store", "Butikk"), selection: $store) {
                        ForEach(enabledStores) { store in
                            Text(store.displayName).tag(store)
                        }
                    }
                    TextField(text("Estimated price", "Estimert pris"), value: $item.estimatedUnitPrice, format: .number)
                        .keyboardType(.decimalPad)
                    Toggle(text("Save this price for future comparisons", "Lagre denne prisen for fremtidige sammenligninger"), isOn: $savePriceToDatabase)
                }

                Section(text("Planning", "Planlegging")) {
                    Toggle(text("Needed by date", "Trengs innen dato"), isOn: $useNeededByDate)
                    if useNeededByDate {
                        DatePicker(text("Needed by", "Trengs innen"), selection: $neededBy, displayedComponents: .date)
                    }
                    Toggle(text("Checked", "Avkrysset"), isOn: $item.isChecked)
                    TextField(text("Notes", "Notater"), text: $item.notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            .navigationTitle(text("Edit Item", "Rediger vare"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(text("Cancel", "Avbryt")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(text("Done", "Ferdig"), action: save)
                        .disabled(item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        item.targetStoreRawValue = store.rawValue
        item.neededBy = useNeededByDate ? neededBy : nil
        if savePriceToDatabase, item.estimatedUnitPrice > 0 {
            upsertStorePrice()
        }
        dismiss()
    }

    private func upsertStorePrice() {
        let normalizedName = StorePriceMatcher.normalize(item.name)
        let quantity = Double(item.quantity.replacingOccurrences(of: ",", with: ".")) ?? 1
        if let existing = storePrices.first(where: {
            StorePriceMatcher.normalize($0.itemName) == normalizedName && $0.storeRawValue == store.rawValue
        }) {
            existing.itemName = item.name
            existing.price = item.estimatedUnitPrice
            existing.quantity = quantity
            existing.unit = item.unit
            existing.currency = currencyCode
            existing.source = "shopping"
            existing.updatedAt = .now
        } else {
            modelContext.insert(StorePrice(itemName: item.name, store: store, price: item.estimatedUnitPrice, quantity: quantity, unit: item.unit, currency: currencyCode, source: "shopping"))
        }
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

struct PriceTrackerView: View {
    let language: AppLanguage
    let currencyCode: String
    let enabledStores: [GroceryStore]
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StorePrice.itemName) private var prices: [StorePrice]
    @State private var showAddPrice = false
    @State private var editingPrice: StorePrice?
    @State private var searchText = ""
    @State private var selectedStoreFilter: GroceryStore?

    private var enabledStoreRawValues: Set<String> {
        Set(enabledStores.map(\.rawValue))
    }

    private var visiblePrices: [StorePrice] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return prices
            .filter { enabledStoreRawValues.contains($0.storeRawValue) }
            .filter { selectedStoreFilter == nil || $0.storeRawValue == selectedStoreFilter?.rawValue }
            .filter { query.isEmpty || $0.itemName.localizedCaseInsensitiveContains(query) }
            .sorted { lhs, rhs in
                if lhs.itemName.localizedCaseInsensitiveCompare(rhs.itemName) != .orderedSame {
                    return lhs.itemName.localizedCaseInsensitiveCompare(rhs.itemName) == .orderedAscending
                }
                return lhs.price < rhs.price
            }
    }

    private var itemGroups: [(name: String, prices: [StorePrice])] {
        let grouped = Dictionary(grouping: visiblePrices) { StorePriceMatcher.normalize($0.itemName) }
        return grouped.keys.sorted().map { key in
            let groupPrices = grouped[key] ?? []
            return (groupPrices.first?.itemName ?? key, groupPrices)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                controlsSection

                if itemGroups.isEmpty {
                    ContentUnavailableView(text("No prices tracked", "Ingen priser lagret"), systemImage: "tag", description: Text(text("Add supermarket prices manually or scan receipts to build comparisons by store.", "Legg inn butikkpriser manuelt eller skann kvitteringer for å bygge sammenligninger per butikk.")))
                } else {
                    ForEach(itemGroups, id: \.name) { group in
                        Section(group.name) {
                            ForEach(group.prices) { price in
                                StorePriceRow(price: price, language: language, currencyCode: currencyCode)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        editingPrice = price
                                    }
                            }
                            .onDelete { offsets in
                                deletePrices(offsets: offsets, from: group.prices)
                            }
                        }
                    }
                }
            }
            .navigationTitle(text("Prices", "Priser"))
            .searchable(text: $searchText, prompt: text("Search items", "Søk etter varer"))
            .toolbar {
                Button {
                    showAddPrice = true
                } label: {
                    Label(text("Add Price", "Legg til pris"), systemImage: "plus")
                }
            }
            .sheet(isPresented: $showAddPrice) {
                StorePriceFormView(language: language, currencyCode: currencyCode, enabledStores: enabledStores)
            }
            .sheet(item: $editingPrice) { price in
                EditStorePriceView(price: price, language: language, currencyCode: currencyCode, enabledStores: enabledStores)
            }
        }
    }

    private var summarySection: some View {
        Section {
            HStack(spacing: 12) {
                ShoppingMetricTile(title: text("Items", "Varer"), value: "\(Set(visiblePrices.map { StorePriceMatcher.normalize($0.itemName) }).count)", icon: "shippingbox")
                ShoppingMetricTile(title: text("Price records", "Prislogger"), value: "\(visiblePrices.count)", icon: "tag")
            }

            if let cheapest = visiblePrices.min(by: { $0.price < $1.price }) {
                Label(text("Lowest saved price", "Laveste lagrede pris") + ": \(cheapest.itemName) · \(cheapest.store.displayName) · \(cheapest.price.formattedCurrency(code: cheapest.currency))", systemImage: "arrow.down.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var controlsSection: some View {
        Section(text("Filters", "Filtre")) {
            Picker(text("Store", "Butikk"), selection: $selectedStoreFilter) {
                Text(text("All tracked stores", "Alle valgte butikker")).tag(nil as GroceryStore?)
                ForEach(enabledStores) { store in
                    Text(store.displayName).tag(store as GroceryStore?)
                }
            }
        }
    }

    private func deletePrices(offsets: IndexSet, from source: [StorePrice]) {
        for index in offsets {
            modelContext.delete(source[index])
        }
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private struct StorePriceRow: View {
    let price: StorePrice
    let language: AppLanguage
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Label(price.store.displayName, systemImage: "storefront")
                    .font(.headline)
                Spacer()
                Text(price.price.formattedCurrency(code: price.currency.isEmpty ? currencyCode : price.currency))
                    .font(.subheadline.weight(.semibold))
            }

            Text("\(price.amountDescription) · \(price.source.capitalized)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(price.updatedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }
}

private struct StorePriceFormView: View {
    let language: AppLanguage
    let currencyCode: String
    let enabledStores: [GroceryStore]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var itemName = ""
    @State private var store: GroceryStore
    @State private var price = 0.0
    @State private var quantity = 1.0
    @State private var unit = "stk"
    @State private var source = "manual"

    init(language: AppLanguage, currencyCode: String, enabledStores: [GroceryStore]) {
        self.language = language
        self.currencyCode = currencyCode
        self.enabledStores = enabledStores
        _store = State(initialValue: enabledStores.first ?? .rema1000)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(text("Item", "Vare")) {
                    TextField(text("Item name", "Varenavn"), text: $itemName)
                    Picker(text("Store", "Butikk"), selection: $store) {
                        ForEach(enabledStores) { store in
                            Text(store.displayName).tag(store)
                        }
                    }
                }

                Section(text("Price", "Pris")) {
                    TextField(text("Price", "Pris") + " (\(currencyCode))", value: $price, format: .number)
                        .keyboardType(.decimalPad)
                    TextField(text("Quantity", "Mengde"), value: $quantity, format: .number)
                        .keyboardType(.decimalPad)
                    TextField(text("Unit", "Enhet"), text: $unit)
                    TextField(text("Source", "Kilde"), text: $source)
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle(text("New Price", "Ny pris"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(text("Cancel", "Avbryt")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(text("Save", "Lagre"), action: save)
                        .disabled(itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || price <= 0)
                }
            }
        }
    }

    private func save() {
        modelContext.insert(StorePrice(itemName: itemName, store: store, price: price, quantity: quantity, unit: unit, currency: currencyCode, source: source.isEmpty ? "manual" : source))
        dismiss()
    }

    private func text(_ english: String, _ norwegian: String) -> String {
        language == .english ? english : norwegian
    }
}

private struct EditStorePriceView: View {
    @Bindable var price: StorePrice
    let language: AppLanguage
    let currencyCode: String
    let enabledStores: [GroceryStore]
    @Environment(\.dismiss) private var dismiss
    @State private var store: GroceryStore

    init(price: StorePrice, language: AppLanguage, currencyCode: String, enabledStores: [GroceryStore]) {
        self.price = price
        self.language = language
        self.currencyCode = currencyCode
        self.enabledStores = enabledStores
        _store = State(initialValue: price.store)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(text("Item", "Vare")) {
                    TextField(text("Item name", "Varenavn"), text: $price.itemName)
                    Picker(text("Store", "Butikk"), selection: $store) {
                        ForEach(enabledStores) { store in
                            Text(store.displayName).tag(store)
                        }
                    }
                }

                Section(text("Price", "Pris")) {
                    TextField(text("Price", "Pris") + " (\(currencyCode))", value: $price.price, format: .number)
                        .keyboardType(.decimalPad)
                    TextField(text("Quantity", "Mengde"), value: $price.quantity, format: .number)
                        .keyboardType(.decimalPad)
                    TextField(text("Unit", "Enhet"), text: $price.unit)
                    TextField(text("Source", "Kilde"), text: $price.source)
                        .textInputAutocapitalization(.never)
                    DatePicker(text("Updated", "Oppdatert"), selection: $price.updatedAt)
                }
            }
            .navigationTitle(text("Edit Price", "Rediger pris"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(text("Done", "Ferdig")) {
                        price.storeRawValue = store.rawValue
                        if price.currency.isEmpty {
                            price.currency = currencyCode
                        }
                        dismiss()
                    }
                }
            }
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
