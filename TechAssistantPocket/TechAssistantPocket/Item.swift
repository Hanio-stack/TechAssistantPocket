//
//  Item.swift
//  TechAssistantPocket
//
//  Created by 腐った卵 on 2026/09/19.
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
