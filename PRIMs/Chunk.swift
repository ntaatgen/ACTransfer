//
//  Chunk.swift
//  actr
//
//  Created by Niels Taatgen on 3/1/15.
//  Copyright (c) 2015 Niels Taatgen. All rights reserved.
//

import Foundation

class Chunk: NSObject, NSCoding {
    /// Name of the chunk
    let name: String
    /// Model in which the chunk is defined
    unowned let model: Model
    /// Time at which chunk entered DM. Nil if not a DM chunk (e.g., in a buffer)
    var creationTime: Double? = nil
    /// Number of references. Assume a single reference on creation
    var references: Int = 1
    /// Dictionary with slot-value pairs, initially empty
    var slotvals = [String:Value]()
    /// List of times at which chunks has been reinforced (assuming non-optimized learning)
    var referenceList = [Double]()
    /// How many other chunks does this chunk appear in?
    var fan: Int = 0
    /// What was the last noise value. Noise is only updated as time progresses
    var noiseValue: Double = 0
    /// At what time was noise last updated
    var noiseTime: Double = -1
    /// If base-level activation is fixed, this has a value
    var fixedActivation: Double? = nil
    /// Order in which the slots of the chunk are printed
    var printOrder: [String] = []
    /// Sji values
    var assocs: [String:Assocs] = [:]// [String:(Double,Int,Int)] = [:] // Sji table - Name: (Sji, int?, F(Cj))
    /// Task number that refers to the file that the chunk was defined in
    var definedIn: [Int] = []
    
    /**
    - returns: the type of the chunk, or empty string if there isn't one defined
    */
    var type: String {
        if let tp = slotvals["isa"] {
            return tp.description
        } else {
            return ""
        }
    }
    
    init (s: String, m: Model) {
        name = s
        model = m
    }
    
    required convenience init?(coder aDecoder: NSCoder) {
        guard let name = aDecoder.decodeObjectForKey("name") as? String,
            let model = aDecoder.decodeObjectForKey("model") as? Model,
            let slotvals = aDecoder.decodeObjectForKey("slotvals") as? [String:String],
            let printOrder = aDecoder.decodeObjectForKey("printorder") as? [String],
            let referenceList = aDecoder.decodeObjectForKey("referencelist") as? [Double],
            let assoc1 = aDecoder.decodeObjectForKey("assoc1") as? [String: Double],
            let assoc2 = aDecoder.decodeObjectForKey("assoc2") as? [String: Int]
            else { return nil }
        self.init(s: name, m: model)
        for (slot,value) in slotvals {
            self.slotvals[slot] = Value.Text(value)
        }
        self.printOrder = printOrder
        self.fan = Int(aDecoder.decodeIntForKey("fan"))
        self.references = Int(aDecoder.decodeIntForKey("references"))
        let creationTime = aDecoder.decodeDoubleForKey("creationtime")
        self.creationTime = creationTime == -1.0 ? nil : creationTime
        let fixedActivation = aDecoder.decodeDoubleForKey("fixedactivation")
        self.fixedActivation = fixedActivation == -1000.0 ? nil : fixedActivation
        self.referenceList = referenceList
        for (chunk,value) in assoc1 {
            self.assocs[chunk] = Assocs(name: chunk, sji: value, opLearning: assoc2[chunk]!)
        }
    
    }

    func encodeWithCoder(coder: NSCoder) {
        coder.encodeObject(self.name, forKey: "name")
        coder.encodeObject(self.model, forKey: "model")
        var slotvals: [String:String] = [:]
        for (slot,value) in self.slotvals {
            slotvals[slot] = value.description
        }
        coder.encodeObject(slotvals, forKey: "slotvals")
        coder.encodeObject(printOrder, forKey: "printorder")
        coder.encodeInt(Int32(fan), forKey: "fan")
        coder.encodeInt(Int32(references), forKey: "references")
        coder.encodeDouble(creationTime ?? -1.0, forKey: "creationtime")
        coder.encodeObject(self.referenceList, forKey: "referencelist")
        coder.encodeDouble(fixedActivation ?? -1000.0, forKey: "fixedactivation")
        var assoc1: [String:Double] = [:]
        var assoc2: [String:Int] = [:]
        for (chunk, value) in assocs {
            assoc1[chunk] = value.sji
            assoc2[chunk] = value.operatorLearning
        }
        coder.encodeObject(assoc1, forKey: "assoc1")
        coder.encodeObject(assoc2, forKey: "assoc2")
    }
    
    /// A string with a printout of the Chunk
    override var description: String {
        get {
            var s = "\(name)\n"
            for slot in printOrder {
                if let val = slotvals[slot] {
                    s += "  \(slot)  \(val)\n"
                }
            }
            return s
        }
    }
    
    /**
    - returns: A copy of the chunk with a new name
    */
    @nonobjc
    func copy() -> Chunk {
        let newChunk = model.generateNewChunk(self.name)
        newChunk.slotvals = self.slotvals
        newChunk.printOrder = self.printOrder
        return newChunk
    }
    
    /**
    - returns: A copy of the chunk with the same name
    */
    func copyLiteral() -> Chunk {
        let newChunk = Chunk(s: self.name, m: self.model)
        newChunk.slotvals = self.slotvals
        newChunk.printOrder = self.printOrder
        return newChunk
    }
    
    /**
    - parameter ch: A chunk

    - returns: Whether the chunk in the parameter is in one of the slots of the chunk
    */
    func inSlot(ch: Chunk) -> Bool {
        for (_,value) in ch.slotvals {
            if value.chunk() === self {
                return true
            }
        }
        return false
    }
    
    /**
    Set the creation time of the chunk to the current time
    */
    func startTime() {
        creationTime = model.time
        if !model.dm.optimizedLearning {
            referenceList.append(model.time)
        }
    }
    
    func setBaseLevel(timeDiff: Double, references: Int) {
        creationTime = model.time + timeDiff
        if model.dm.optimizedLearning {
            self.references = references
        } else {
            let increment = -timeDiff / Double(references)
            for i in 0..<references {
                let referenceTime = creationTime! + Double(i) * increment
              referenceList.append(referenceTime)
            }
        }
    }

    /**
    - returns: The current baselevel activation of the chunk
    */
    func baseLevelActivation () -> Double {
        if creationTime == nil { return 0 }
 
        let fixedComponent = fixedActivation == nil ? 0.0 : exp(fixedActivation!)
        if model.dm.optimizedLearning {
            return log(fixedComponent + (Double(references) * pow(model.time - creationTime! + 0.05, -model.dm.baseLevelDecay)) / (1 - model.dm.baseLevelDecay))
//            let x = log((Double(references)/(1 - model.dm.baseLevelDecay)))
//            let y = model.dm.baseLevelDecay * log(model.time - creationTime!)
//            return x - y
        } else {
            return log(fixedComponent + self.referenceList.map{ pow((self.model.time - $0 + 0.05),(-self.model.dm.baseLevelDecay))}.reduce(0.0, combine: + )) // Wew! almost lisp! This is the standard baselevel equation
        }
    }
    
    /**
    Add a reference to the chunk for the current model time
    */
    func addReference() {
        if creationTime == nil { return }
        if model.dm.optimizedLearning {
            references += 1
//            println("Added reference to \(self) references = \(references)")
        }
        else {
            referenceList.append(model.time)
        }
    }
    
    func setSlot(slot: String, value: Chunk) {
        if slotvals[slot] == nil { printOrder.append(slot) }
        slotvals[slot] = Value.Symbol(value)
    }
    
    @nonobjc
    func setSlot(slot: String, value: Double) {
        if slotvals[slot] == nil { printOrder.append(slot) }
        slotvals[slot] = Value.Number(value)
    }
    
    @nonobjc
    func setSlot(slot: String, value: String) {
        if slotvals[slot] == nil { printOrder.append(slot) }
        let possibleNumVal = string2Double(value) 
        if possibleNumVal != nil {
            slotvals[slot] = Value.Number(possibleNumVal!)
        }
        if let chunk = model.dm.chunks[value] {
            slotvals[slot] = Value.Symbol(chunk)
        } else {
            slotvals[slot] = Value.Text(value)
        }
    }
    
    @nonobjc
    func setSlot(slot: String, value: Value) {
        if slotvals[slot] == nil { printOrder.append(slot) }
           slotvals[slot] = value
    }
    
    func slotValue(slot: String) -> Value? {
        if slot == "slot0" {
            return slotvals[slot] ?? .Symbol(self)
        } else {
            return slotvals[slot]
        }
    }
    
//    double getSji (Chunk cj, Chunk ci)
//    {
//    if (cj.appearsInSlotsOf(ci)==0 && cj.name!=ci.name) return 0;
//    else return model.declarative.maximumAssociativeStrength - Math.log(cj.fan);
//    }
    
    func appearsInSlotOf(chunk: Chunk) -> Bool {
        for (_,value) in chunk.slotvals {
            switch value {
            case .Symbol(let valChunk):
                if valChunk.name==self.name { return true }
            default: break
            }
        }
        return false
    }
    
    func frequencyInSlotOf(chunk: Chunk) -> Int {
        var freq = 0
        if(self.name == "mf18") {
            print(chunk)
        }
        for (_,value) in chunk.slotvals {
            switch value {
            case .Symbol(let valChunk):
                if valChunk.name==self.name {
                    freq = freq + 1
                }
            default: break
            }
            if(self.name == "mf18") {
                print(freq)
            }
        }
        return freq
    }

    
    /**
    Add noise to an association value. This is only used for the Sji between goals and operators

    - returns: An Sji value with noise included
    */
    
    func calculateSji(sji: (Double,Int)) -> Double {
        let (base, references) = sji
        if references == 0 {
            return base
        } else {
            return base + model.dm.explorationExploitationFactor * actrNoise(model.dm.defaultOperatorAssoc) / sqrt(Double(references))
        }
    }
    
    /**
    Calculate the association between self and another chunk
    The chunk that receives the activation has the Sji in its list
    
    - parameter chunk: the chunk that the association is with
    
    - returns: the Sji value
    */
    func sji(chunk: Chunk) -> Double {
        if let value = chunk.assocs[self.name] {
            return calculateSji((value.sji, value.operatorLearning))
        } else if self.appearsInSlotOf(chunk) {
            return model.dm.maximumAssociativeStrength - log(Double(self.fan))
        }
        return 0.0
    }
    
    /**
     Retrieve the frequency F(Ni & Cj), how often has chunk i been retrieved with chunk j in the context
     - parameter chunk: the chunk that the association is with
     
     - returns: the Sji value
     */
    func freqNiCj(chunk: Chunk) -> Int {
        if let value = chunk.assocs[self.name] {
            return value.frequency
        }
        return 0
    }
    
    /**
    Posterior Strength Equation
    */
//    func posteriorStrength(source: Chunk) -> Double {
//        var contextFrequency = 0
//        source.appearsInSlotOf(model.buffers["input"])
//        if  let bufferChunk = model.buffers["input"] { // The current context is only the input buffer, because that works for us
//            for (_,value) in bufferChunk.slotvals {
//                switch value {
//                case .Symbol(let valchunk):
//                    if valchunk == source.
//                        contextFrequency += 1
//                default:
//                    break
//                }
//            }
//        }
//        model.dm.assoc +
//        
//        let prior = priorStrength(source)
//        let assoc = 0
//        let fcj = 0
//        let empiricalS = 0
//        
//        return 0.0
//    }
//    
    /**
//    Prior Strength Equation
//    */
//    func priorStrength(source: Chunk) -> Double {
//        let m = Double(model.dm.chunks.count)
//        var n = 0.0
//        for (_, ch) in model.dm.chunks {
//            for (_, slot) in ch.slotvals {
//                switch(slot) {
//                case .Symbol(let slotval):
//                    if source == slotval {
//                        n = n + 1
//                    }
//                default:
//                    break
//                }
//            }
//        }
//        if n == 0 {
//            return 0.0
//        } else {
//            return (m / n)
//        }
//    }
    
    /**
    Calculate the spreading activation for associative learning from a certain buffer
     
     This is based on the functions used in ACT-R 4, see Lebiere (1999)
     Instead of Rji we use the default Sji function of ACT-R 7 (Sji = S - ln(fanj))
     The prior strength of association is 1.
    
     - parameter bufferName: The name of the buffer - for now it only works for input
     - parameter assoc: The value of the assoc parameter
     - returns: The amount of spreading activation from this buffer
    */
    func alSpreadingFromBuffer(bufferName: String, assocValue: Double) -> Double {
        print("hoi")
        if assocValue == 0 { return 0 }
        var totalPosteriorSji = 0.0
        var totalSlots = 0
        if let bufferChunk = model.buffers[bufferName] {
//            print(bufferChunk.slotvals)
//            print("hier")
//            print(bufferChunk.slotvals["isa"]!)
//            print("\n")
//            if bufferChunk.slotvals["isa"]! == "fact" {
                for (_,value) in bufferChunk.slotvals {
                    print(value)
                    switch value {
                    case .Symbol(let valchunk):
                        let posteriorSji = log((assocValue + Double(freqNiCj(valchunk)) * sji(valchunk)) / (assocValue + Double(freqNiCj(valchunk))))
                        totalPosteriorSji += posteriorSji
                        if valchunk.assocs[self.name] != nil {
                            valchunk.assocs[self.name]!.posteriorSji = posteriorSji
                            print("boe")
                        }
                        totalSlots += 1
                    default:
                        break
                    }
                }
//            }
        
        }
        return totalPosteriorSji
    }
    
    /**
    Calculate the spreading of activation from a certain buffer

    - parameter bufferName: The name of the buffer
    - parameter spreadingParameterValue: The amount of spreading from that particular buffer
    - returns: The amound of spreading activation from this buffer
    */
    func spreadingFromBuffer(bufferName: String, spreadingParameterValue: Double) -> Double {
        if spreadingParameterValue == 0 { return 0 }
        var totalSji = 0.0
        if  let bufferChunk = model.buffers[bufferName] {
            var totalSlots: Int = 0
            for (_,value) in bufferChunk.slotvals {
                switch value {
                case .Symbol(let valchunk):
                    totalSji += valchunk.sji(self)
//                    if valchunk.sji(self) != 0.0 {
//                        println("Buffer \(bufferName) slot \(value.description) to \(self.name) spreading \(valchunk.sji(self))")
//                    }
                    totalSlots += 1
                default:
                    break
                }
            }
            return (totalSlots==0 ? 0 : totalSji * (spreadingParameterValue / Double(totalSlots)))

        }
        return 0.0
    }
    
    /**
    Calculate spreading activation for the chunk from the goal
    
    Can be calculated in three ways, either standard ACT-R's equation, or by making spreading dependent on the activation of the chunks in the goal slots, or by using associative learning.
    
    - returns: The amount of spreading activation
    */
    func spreadingActivation() -> Double {
        if creationTime == nil {return 0}
        var totalSpreading: Double = 0
        if model.dm.associativeLearning && self.type != "operator" {
            totalSpreading += alSpreadingFromBuffer("input", assocValue: model.dm.assoc)
        } else {
            if model.dm.goalSpreadingByActivation {
                if let goal=model.buffers["goal"] {
                    for (_,value) in goal.slotvals {
                        switch value {
                        case .Symbol(let valchunk):
                            totalSpreading += valchunk.sji(self) * max(0,valchunk.baseLevelActivation())
                        default:
                            break
                        }
                    }
                }
            } else {
                totalSpreading += spreadingFromBuffer("goal", spreadingParameterValue: model.dm.goalActivation)
            }
            totalSpreading += spreadingFromBuffer("input", spreadingParameterValue: model.dm.inputActivation)
            totalSpreading += spreadingFromBuffer("retrievalH", spreadingParameterValue: model.dm.retrievalActivation)
            totalSpreading += spreadingFromBuffer("imaginal", spreadingParameterValue: model.dm.imaginalActivation)
            //        let val = spreadingFromBuffer("imaginal", spreadingParameterValue: model.dm.imaginalActivation)
            //        print("Spreading from imaginal to \(self.name) is \(val) \(model.dm.imaginalActivation)")
        }
        
        return totalSpreading
    }
    
    func calculateNoise() -> Double {
        if model.time != noiseTime {
            noiseValue = (model.dm.activationNoise == nil ? 0.0 : actrNoise(model.dm.activationNoise!))
            noiseTime = model.time
        }
            return noiseValue
    }
    
    func activation() -> Double {
        if creationTime == nil {return 0}
        return  self.baseLevelActivation()
            + self.spreadingActivation() + calculateNoise()
    }
    
    func mergeAssocs(newchunk: Chunk) {
        for (name,value) in newchunk.assocs {
            if assocs[name] == nil {
                assocs[name] = value
            } else {
                assocs[name] = Assocs(name: name, sji: max(assocs[name]!.sji,value.sji), opLearning: assocs[name]!.operatorLearning + value.operatorLearning)
            }
        }
    }
    
}

func == (left: Chunk, right: Chunk) -> Bool {
    // Are two chunks equal? They are if they have the same slots and values
    if left.slotvals.count != right.slotvals.count { return false }
    for (slot1,value1) in left.slotvals {
        if let rightVal = right.slotvals[slot1] {
            if value1.description != rightVal.description { return false }
//            switch (rightVal,value1) {
//            case (.Number(let val1),.Number(let val2)): if val1 != val2 { return false }
//            case (.Text(let s1), .Text(let s2)): if s1 != s2 { return false }
//            case (.Symbol(let c1), .Symbol(let c2)): if c1 !== c2 { return false }
//            default: return false
//            }
        } else { return false }
    }
    return true
}

func != (left: Chunk, right: Chunk) -> Bool {
    return !(left == right)
}

