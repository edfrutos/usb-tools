//
//  Item.swift
//  USBLab
//
//  Created by Eugenio de Frutos Sanchez on 9/12/25.
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
