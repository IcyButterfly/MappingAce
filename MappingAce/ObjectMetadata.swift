//
//  ObjectMetadata.swift
//  Mapping
//
//  Created by ET|冰琳 on 16/10/19.
//  Copyright © 2016年 Ice Butterfly. All rights reserved.
//

import Foundation


enum MetadataKind {
    case `struct`
    case `class`
    case ObjCClassWrapper
}
 
struct ObjectMetadata {
    public var kind: MetadataKind
    public var propertyNames: [String]
    public var propertyTypes: [Any.Type]
    public var propertyOffsets: [Int]
}


func MetadataInfoFor(type: Any.Type) -> ObjectMetadata{
    
    let typePointer = unsafeBitCast(type, to: UnsafePointer<Struct>.self)
    let typeStruct = typePointer.pointee
    let kind = typeStruct.kind
    
    struct TypeInfoHashTable{
        static var table: [UnsafePointer<Struct> : ObjectMetadata] = [:]
    }
    
    if let structInfo = TypeInfoHashTable.table[typePointer]{
        return structInfo
    }

    if kind == 1{
        let info = nominalTypeOfStruct(typePointer: typePointer)
        TypeInfoHashTable.table[typePointer] = info
        return info
    }
    else if kind == 2{
        fatalError("not implement for enum")
    }else if kind == 14{
        return ObjectMetadata(kind: .ObjCClassWrapper, propertyNames: [], propertyTypes: [], propertyOffsets: [])
    }
    else if kind > 4096{
        let info = nominalTypeOfClass(typePointer: typePointer)
        TypeInfoHashTable.table[typePointer] = info
        return info
    }
    fatalError("not implement type")
}

private func nominalTypeOfStruct(typePointer: UnsafePointer<Struct>) -> ObjectMetadata{
    
    let intPointer = typePointer.withMemoryRebound(to: Int.self, capacity: 1, { $0 })
    
    let nominalTypeBase = intPointer.advanced(by: 1)
    
    let int8Type = nominalTypeBase.withMemoryRebound(to: Int8.self, capacity: 1, { $0 })

    let nominalTypePointer = int8Type.advanced(by: typePointer.pointee.nominalTypeDescriptorOffset)
    
    let nominalType = nominalTypePointer.withMemoryRebound(to: NominalTypeDescriptor.self, capacity: 1, { $0 })
    let numberOfField = Int(nominalType.pointee.numberOfFields)
    
    let int32NominalType = nominalType.withMemoryRebound(to: Int32.self, capacity: 1, { $0 })
    let fieldBase = int32NominalType.advanced(by: Int(nominalType.pointee.FieldOffsetVectorOffset))
    
    let int8FieldBasePointer = fieldBase.withMemoryRebound(to: Int8.self, capacity: 1, { $0 })
    let fieldNamePointer = int8FieldBasePointer.advanced(by: Int(nominalType.pointee.fieldNames))
    
    let fieldNames = getFieldNames(pointer: fieldNamePointer, fieldCount: numberOfField)
    
    let int32NominalFunc = nominalType.withMemoryRebound(to: Int32.self, capacity: 1, { $0 }).advanced(by: 4)
    
    let nominalFunc = int32NominalFunc.withMemoryRebound(to: Int8.self, capacity: 1, { $0 }).advanced(by: Int(nominalType.pointee.getFieldTypes))
    
    
    let fieldType = getType(pointer: nominalFunc, fieldCount: numberOfField)
    
    let offsetPointer = intPointer.advanced(by: Int(nominalType.pointee.FieldOffsetVectorOffset))
    var offsetArr: [Int] = []
    
    for i in 0..<numberOfField {
        let offset = offsetPointer.advanced(by: i)
        offsetArr.append(offset.pointee)
    }
    
    let info = ObjectMetadata(kind: .struct,propertyNames: fieldNames, propertyTypes: fieldType, propertyOffsets: offsetArr)
    return info
}

 

private func getType(pointer nominalFunc: UnsafePointer<Int8>, fieldCount numberOfField: Int) -> [Any.Type]{
        
    let funcPointer = unsafeBitCast(nominalFunc, to: FieldsTypeAccessor.self)
    let funcBase = funcPointer(nominalFunc.withMemoryRebound(to: Int.self, capacity: 1, { $0 }))
    
    
    var types: [Any.Type] = []
    for i in 0..<numberOfField {
        let typeFetcher = funcBase.advanced(by: i).pointee
        let type = unsafeBitCast(typeFetcher, to: Any.Type.self)
        types.append(type)
    }
    
    return types
}


private func getFieldNames(pointer: UnsafePointer<Int8>, fieldCount numberOfField: Int) -> [String]{
    
    return Array<String>(utf8Strings: pointer)
}



private func nominalTypeOfClass(typePointer t: UnsafePointer<Struct>) -> ObjectMetadata{
    
    let typePointer = t.withMemoryRebound(to: NominalTypeDescriptor.Class.self, capacity: 1, { $0 })
    return nominalTypeOf(pointer: typePointer)
    
}

private func nominalTypeOf(pointer typePointer: UnsafePointer<NominalTypeDescriptor.Class>) -> ObjectMetadata{
    
    let intPointer = typePointer.withMemoryRebound(to: Int.self, capacity: 1, { $0 })
    
    let typePointee = typePointer.pointee
    let superPointee = typePointee.super_
    
    var superObject: ObjectMetadata
    
    if Int(bitPattern: typePointer.pointee.isa) == 14 || Int(bitPattern: superPointee) == 0{
        superObject = ObjectMetadata(kind: .ObjCClassWrapper, propertyNames: [], propertyTypes: [], propertyOffsets: [])
        return superObject
    }else{
        superObject = nominalTypeOf(pointer: superPointee)
        superObject.kind = .class
    }
    
    let nominalTypeOffset = (MemoryLayout<Int>.size == MemoryLayout<Int64>.size) ? 8 : 11
    let nominalTypeInt = intPointer.advanced(by: nominalTypeOffset)


    let nominalTypeint8 = nominalTypeInt.withMemoryRebound(to: Int8.self, capacity: 1, { $0 })
    let des = nominalTypeint8.advanced(by: typePointee.Description)
    
    let nominalType = des.withMemoryRebound(to: NominalTypeDescriptor.self, capacity: 1, { $0 })
    
    let numberOfField = Int(nominalType.pointee.numberOfFields)
    
    let int32NominalType = nominalType.withMemoryRebound(to: Int32.self, capacity: 1, { $0 })
    let fieldBase = int32NominalType.advanced(by: 3)//.advanced(by: Int(nominalType.pointee.FieldOffsetVectorOffset))
    
    let int8FieldBasePointer = fieldBase.withMemoryRebound(to: Int8.self, capacity: 1, { $0 })
    let fieldNamePointer = int8FieldBasePointer.advanced(by: Int(nominalType.pointee.fieldNames))
    
    let fieldNames = getFieldNames(pointer: fieldNamePointer, fieldCount: numberOfField)
    superObject.propertyNames.append(contentsOf: fieldNames)
    
    let int32NominalFunc = nominalType.withMemoryRebound(to: Int32.self, capacity: 1, { $0 }).advanced(by: 4)
    
    let nominalFunc = int32NominalFunc.withMemoryRebound(to: Int8.self, capacity: 1, { $0 }).advanced(by: Int(nominalType.pointee.getFieldTypes))
    
    let fieldType = getType(pointer: nominalFunc, fieldCount: numberOfField)
    superObject.propertyTypes.append(contentsOf: fieldType)
    
    let offsetPointer = intPointer.advanced(by: Int(nominalType.pointee.FieldOffsetVectorOffset))
    var offsetArr: [Int] = []
    
    for i in 0..<numberOfField {
        let offset = offsetPointer.advanced(by: i)
        offsetArr.append(offset.pointee)
    }
    superObject.propertyOffsets.append(contentsOf: offsetArr)
    
    return superObject
}
 
 
protocol UTF8Initializable {
    init?(validatingUTF8: UnsafePointer<CChar>)
}

extension String : UTF8Initializable {}

extension Array where Element : UTF8Initializable {
    
    init(utf8Strings: UnsafePointer<CChar>) {
        var strings = [Element]()
        var p = utf8Strings
        while let string = Element(validatingUTF8: p) {
            strings.append(string)
            while p.pointee != 0 {
                p = p.advanced(by: 1)
            }
            p = p.advanced(by: 1)
            guard p.pointee != 0 else { break }
        }
        self = strings
    }
}
