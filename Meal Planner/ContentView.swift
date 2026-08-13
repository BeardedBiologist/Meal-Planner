//
//  ContentView.swift
//  Meal Planner
//
//  Created by Joshua James O'Connor on 13/08/2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var authManager = AuthenticationManager.shared

    var body: some View {
        if authManager.isAuthenticated {
            MealPlannerHomeView()
        } else {
            LandingView()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
