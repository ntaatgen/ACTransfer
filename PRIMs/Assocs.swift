//
//  Assocs.swift
//  PRIMs
//
//  Created by Trudy Buwalda on 23/11/16.
//  Copyright © 2016 Niels Taatgen. All rights reserved.
//


class Assocs {
    let name: String
    var sji: Double
    var unknownValue: Int
    var frequency: Int
    
    init (s: String) {
        self.name = s
        self.sji = 0.0
        self.unknownValue = 0
        self.frequency = 0
    }
    
    init (name: String, sji: Double, unknown: Int) {
        self.name = name
        self.sji = sji
        self.unknownValue = unknown
        self.frequency = 0
    }
}


