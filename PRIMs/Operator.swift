//
//  Operator.swift
//  PRIMs
//
//  Created by Niels Taatgen on 7/28/15.
//  Copyright (c) 2015 Niels Taatgen. All rights reserved.
//

import Foundation

/**
    The Operator class contains many of the functions that deal with operators. Most of these still have to be migrated from Model.swift
*/
class Operator {

    unowned let model: Model
    
    init(model: Model) {
        self.model = model
    }

    
    /**
    Reset the operator object
    */
    func reset() {
    }
    
    
    /**
    Determine the amount of overlap between two lists of PRIMs
    */
    func determineOverlap(_ oldList: [String], newList: [String]) -> Int {
        var count = 0
        for prim in oldList {
            if !newList.contains(prim) {
                return count
            }
            count += 1
        }
        return count
    }
    
    /**
    Construct a string of PRIMs from the best matching operators
    */
    func constructList(_ template: [String], source: [String], overlap: Int) -> (String, [String]) {
        var primList = ""
        var primArray = [String]()
        if overlap > 0 {
            for i in 0..<overlap {
                primList =  (primList == "" ? template[i] : template[i] + ";" ) + primList
                primArray.append(template[i])
            }
        }
        for prim in source {
            if !primArray.contains(prim) {
                primList = (primList == "" ? prim : prim + ";" ) + primList
                primArray.append(prim)
            }
        }
        return (primList, primArray)
    }
    
    
    /**
    Add conditions and actions to an operator while trying to optimize the order of the PRIMs to maximize overlap with existing operators 
    */
    func addOperator(_ op: Chunk, conditions: Chunk, actions: [String]) {

        var bestActionMatch: [String] = []
        var bestActionNumber: Int = -1
        var bestActionActivation: Double = -1000
        for (chunkName, chunkActions) in model.dm.operatorCA {
            if let chunkActivation = model.dm.chunks[chunkName]?.baseLevelActivation() {
                let actionOverlap = determineOverlap(chunkActions, newList: actions)
                if (actionOverlap > bestActionNumber) || (actionOverlap == bestActionNumber && chunkActivation > bestActionActivation) {
                    bestActionMatch = chunkActions
                    bestActionNumber = actionOverlap
                    bestActionActivation = chunkActivation
                }
            }
        }
        let (actionString, actionList) = constructList(bestActionMatch, source: actions, overlap: bestActionNumber)
        op.setSlot("condition", value: conditions)
        op.setSlot("action", value: actionString)
        model.dm.operatorCA.append((op.name, actionList))
    }
    
    
    /// List of chosen operators with time
    var previousOperators: [(Chunk,Double)] = []
    
    /**
    Update the Sji's between the current goal(s?) and the operators that have fired. Restrict to updating the goal in G1 for now.
    
    - parameter payoff: The payoff that will be distributed
    */
    func updateOperatorSjis(_ payoff: Double) {
        if !model.dm.goalOperatorLearning || model.reward == 0.0 { return } // only do this when switched on
        let goalChunk = model.formerBuffers["goal"]?.slotvals["slot1"]?.chunk() // take formerBuffers goal, because goal may have been replace by stop or nil
        if goalChunk == nil { return }
        for (operatorChunk,operatorTime) in previousOperators {
            let opReward = model.dm.defaultOperatorAssoc * (payoff - (model.time - operatorTime)) / model.reward
            if operatorChunk.assocs[goalChunk!.name] == nil {
                operatorChunk.assocs[goalChunk!.name] = (0.0, 0)
            }
            operatorChunk.assocs[goalChunk!.name]!.0 += model.dm.beta * (opReward - operatorChunk.assocs[goalChunk!.name]!.0)
            operatorChunk.assocs[goalChunk!.name]!.1 += 1
            if opReward > 0 {
                operatorChunk.addReference() // Also increase baselevel activation of the operator
            }
            if !model.silent {
                model.addToTrace("Updating assoc between \(goalChunk!.name) and \(operatorChunk.name) to \(operatorChunk.assocs[goalChunk!.name]!)", level: 5)
            }
        }
    }
 
    /**
    Create a single chunk out of the contents of the goal, retrieval, input and imaginal buffer
    */
    func buffersToChunk() -> Chunk {
        let chunk = Chunk(s: model.generateName("instance"), m: model)
        for (buffer, bufferString) in [("goal","G"),("retrievalH","RT"),("imaginal","WM"),("input","V")] {
            if model.buffers[buffer] != nil {
                for (slot, value) in model.buffers[buffer]!.slotvals {
                    if slot.hasPrefix("slot") {
                        let newSlotName = bufferString + slot.substring(from: slot.characters.index(slot.startIndex, offsetBy: 4))
                        chunk.setSlot(newSlotName, value: value)
                    }
                }
            }
        }
        return chunk
    }
    
    /**
    Calculate how well the operator matches the current state
 
    - parameter op: The operator to be matched
    - parameter bufferChunk: A chunk made of all the relevant buffers
    - returns: The match score
    */
    func matchScore(op: Chunk, bufferChunk: Chunk) -> Double {
        var score = 0.0
        let conditionChunk = op.slotValue("condition")!.chunk()!
        var slotList: [String] = [] // List of all the slots
        var allValues: [Chunk:[String]] = [:]
        for (slot,value) in conditionChunk.slotvals {
            slotList.append(slot)
            if value.type == "symbol" {
                var slots = allValues[value.chunk()!]
                if slots == nil {
                    allValues[value.chunk()!] = [slot]
                } else {
                    slots!.append(slot)
                    allValues[value.chunk()!] = slots!
                }
             }
        }
        for (slot,_) in bufferChunk.slotvals {
            if !slotList.contains(slot) {
                slotList.append(slot)
            }
        }
        for slot in slotList {
            let bufferValue = bufferChunk.slotvals[slot] ?? Value.Text("nil")
            let operatorValue = conditionChunk.slotvals[slot] ?? Value.Text("nil")
            if !(bufferValue.description == "nil" && operatorValue.description == "nil") {
                if bufferValue.isEqual(operatorValue) {
                    score += 1.0
                }
                if bufferValue.type != operatorValue.type || bufferValue.description == "nil" || operatorValue.description == "nil"  {
                    score -= 3.0
                }
            }
        }
        
        // Now look for patterns. In particular we look at repeated values (chunks) in the example
        // We have already collected duplicate values in repreatedValues
        for (_, slots) in allValues {
            if slots.count > 1 {
                print("Checking pattern in \(op.name)")
                var patternFound = true
                for slot in slots {
                    if bufferChunk.slotvals[slot] == nil || bufferChunk.slotvals[slot]!.type != "symbol" {
                        patternFound = false
                        print("Slot \(slot) does not contain a chunk")
                    }
                }
                if patternFound {
                    let idChunk = bufferChunk.slotvals[slots[0]]!.chunk()!
                    for (slot,value) in bufferChunk.slotvals {
                        if patternFound {
                            if slots.contains(slot) {
                                patternFound = value.chunk()! == idChunk
                                print("Check of slot \(slot) is \(patternFound)")
                            } else {
                                patternFound = value.type != "symbol" || value.chunk()! != idChunk
                                print("Neg Check of slot \(slot) is \(patternFound)")
                            }
                        }
                    }
                }
                score += patternFound ? 5.0 : -1.0
            }
        }
        
        return score
    }
    
    /**
     Retrieve an operator
     */
    func retrieveOperator() -> (Double, Chunk?) {
        var bestMatch: Chunk? = nil
        var bestMatchScore: Double = -100
        let bufferChunk = buffersToChunk()
        print("Checking operators for state \(bufferChunk)")
        model.dm.retrieveError = false
        model.dm.conflictSet = []
        for (_,ch1) in model.dm.chunks {
            if (ch1.type == "operator") &&  !model.dm.finsts.contains(ch1.name) {
                let matchS = matchScore(op: ch1, bufferChunk: bufferChunk)
                if matchS > bestMatchScore {
                    bestMatchScore = matchS
                    bestMatch = ch1
                }
                model.dm.conflictSet.append((ch1, matchS))
            }
        }
        if bestMatch != nil {
            return (0.05, bestMatch)
        } else {
            model.dm.retrieveError = true
            return (model.dm.latency(model.dm.retrievalThreshold), nil)
            
        }
    }
    
    
    /**
    This function finds an applicable operator and puts it in the operator buffer.
    
    - returns: Whether an operator was successfully found
    */
    func findOperator() -> Bool {
        let retrievalRQ = Chunk(s: "operator", m: model)
        retrievalRQ.setSlot("isa", value: "operator")
        var (latency,opRetrieved) = model.dm.retrieve(chunk: retrievalRQ)
            let cfs = model.dm.conflictSet.sorted(by: { (item1, item2) -> Bool in
                let (_,u1) = item1
                let (_,u2) = item2
                return u1 > u2
            })
        if !model.silent {
            model.addToTrace("Conflict Set", level: 5)
            for (chunk,activation) in cfs {
                let outputString = "  " + chunk.name + "A = " + String(format:"%.3f", activation) //+ "\(activation)"
                model.addToTrace(outputString, level: 5)
            }
        }
        model.time += latency
        if opRetrieved == nil {
            if !model.silent {
                model.addToTrace("   No matching operator found", level: 2)
            }
            return false
        }
        if model.dm.goalOperatorLearning {
            let item = (opRetrieved!, model.time - latency)
            previousOperators.append(item)
        }
        if !model.silent {
            if let opr = opRetrieved {
                model.addToTrace("*** Retrieved operator \(opr.name) with spread \(opr.spreadingActivation())", level: 1)
            }
        }
        model.dm.addToFinsts(opRetrieved!)
        model.buffers["goal"]!.setSlot("last-operator", value: opRetrieved!)
        model.buffers["operator"] = opRetrieved!.copy()
        model.formerBuffers["operator"] = opRetrieved!
        
        
        return true
    }
    
    
    /**
    This function carries out productions for the current operator until it has a PRIM that fails, in
    which case it returns false, or until all the conditions of the operator have been tested and
    all actions have been carried out.
    */
    func carryOutProductionsUntilOperatorDone() -> Bool {
        var match: Bool = true
        var first: Bool = true
        while match && model.buffers["operator"]?.slotvals["action"] != nil {
            let inst = model.procedural.findMatchingProduction()
            var pname = inst.p.name
            if pname.hasPrefix("t") {
                pname = String(pname.characters.dropFirst())
            }
            if !model.silent {
                model.addToTrace("Firing \(pname)", level: 3)
            }
            (match, _) = model.procedural.fireProduction(inst, compile: true)
            if first {
                model.time += model.procedural.productionActionLatency
                first = false
            } else {
                model.time += model.procedural.productionAndPrimLatency
            }
        }
        return match
    }
    
    
}
