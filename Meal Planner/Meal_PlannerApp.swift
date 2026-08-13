//
//  Meal_PlannerApp.swift
//  Meal Planner
//
//  Created by Joshua James O’Connor on 13/08/2026.
//

import SwiftUI
import SwiftData

@main
struct Meal_PlannerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            Recipe.self,
            MealPlanEntry.self,
            ShoppingListItem.self,
            StorePrice.self,
            ReceiptLineItem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
