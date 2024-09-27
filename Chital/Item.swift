//
//  Item.swift
//  Chital
//
//  Created by Sheshbabu Chinnakonda on 27/9/24.
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
