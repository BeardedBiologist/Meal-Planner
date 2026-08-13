//
//  Item.swift
//  Meal Planner
//
//  Created by Joshua James O’Connor on 13/08/2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
