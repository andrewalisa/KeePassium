//
//  Meta2.swift
//  KeePassium
//
//  Created by Andrei Popleteev on 2018-03-02.
//  Copyright © 2018 Andrei Popleteev. All rights reserved.
//

import Foundation
//import AEXML

/// Metadata of a KP2 database
final class Meta2: Eraseable {
    public static let generatorName = "KeePassium" // short app name, no version
    public static let defaultMaintenanceHistoryDays: UInt32 = 365
    public static let defaultHistoryMaxItems: Int32 = 10 // -1 for unlimited
    public static let defaultHistoryMaxSize: Int64 = 6*1024*1024 // -1 for unlimited
    
    /// Memory protection configuration of a KP2 database.
    struct MemoryProtection {
        private(set) var isProtectTitle: Bool = false
        private(set) var isProtectUserName: Bool = false
        private(set) var isProtectPassword: Bool = false
        private(set) var isProtectURL: Bool = false
        private(set) var isProtectNotes: Bool = false

        mutating func erase() {
            isProtectTitle = false
            isProtectUserName = false
            isProtectPassword = true
            isProtectURL = false
            isProtectNotes = false
        }
        
        /// - Throws: Xml2.ParsingError
        mutating func load(xml: AEXMLElement) throws {
            assert(xml.name == Xml2.memoryProtection)
            Diag.verbose("Loading XML: memory protection")
            
            erase()
            for tag in xml.children {
                switch tag.name {
                case Xml2.protectTitle:
                    isProtectTitle = Bool(string: tag.value)
                case Xml2.protectUserName:
                    isProtectUserName = Bool(string: tag.value)
                case Xml2.protectPassword:
                    isProtectPassword = Bool(string: tag.value)
                case Xml2.protectURL:
                    isProtectURL = Bool(string: tag.value)
                case Xml2.protectNotes:
                    isProtectNotes = Bool(string: tag.value)
                default:
                    Diag.error("Unexpected XML tag in Meta/MemoryProtection: \(tag.name)")
                    throw Xml2.ParsingError.unexpectedTag(
                        actual: tag.name,
                        expected: "Meta/MemoryProtection/*")
                }
            }
        }
        
        func toXml() -> AEXMLElement {
            Diag.verbose("Generating XML: memory protection")
            let xmlMP = AEXMLElement(name: Xml2.memoryProtection)
            xmlMP.addChild(
                name: Xml2.protectTitle,
                value: isProtectTitle ? Xml2._true : Xml2._false)
            xmlMP.addChild(
                name: Xml2.protectUserName,
                value: isProtectUserName ? Xml2._true : Xml2._false)
            xmlMP.addChild(
                name: Xml2.protectPassword,
                value: isProtectPassword ? Xml2._true : Xml2._false)
            xmlMP.addChild(
                name: Xml2.protectURL,
                value: isProtectURL ? Xml2._true : Xml2._false)
            xmlMP.addChild(
                name: Xml2.protectNotes,
                value: isProtectNotes ? Xml2._true : Xml2._false)
            return xmlMP
        }
    }
    
    private unowned let database: Database2
    private(set) var generator: String
    internal(set) var headerHash: ByteArray? // might be set externally for saving kp2v3 database
    private(set) var settingsChangedTime: Date
    private(set) var databaseName: String
    private(set) var databaseNameChangedTime: Date
    private(set) var databaseDescription: String
    private(set) var databaseDescriptionChangedTime: Date
    private(set) var defaultUserName: String
    private(set) var defaultUserNameChangedTime: Date
    private(set) var maintenanceHistoryDays: UInt32
    /// Database color coded as a CSS-format hex string (e.g. #123456), empty string means transparent
    private(set) var colorString: String
    internal(set) var masterKeyChangedTime: Date
    private(set) var masterKeyChangeRec: Int64
    private(set) var masterKeyChangeForce: Int64
    private(set) var memoryProtection: MemoryProtection
    private(set) var isRecycleBinEnabled: Bool
    private(set) var recycleBinGroupUUID: UUID
    internal(set) var recycleBinChangedTime: Date
    private(set) var entryTemplatesGroupUUID: UUID
    private(set) var entryTemplatesGroupChangedTime: Date
    private(set) var historyMaxItems: Int32
    private(set) var historyMaxSize: Int64
    private(set) var lastSelectedGroupUUID: UUID
    private(set) var lastTopVisibleGroupUUID: UUID
    private(set) var customData: CustomData2
    private(set) var customIcons: [UUID: CustomIcon2]
    
    init(database: Database2) {
        self.database = database
        generator = ""
        headerHash = nil
        settingsChangedTime = Date.now
        databaseName = ""
        databaseNameChangedTime = Date.now
        databaseDescription = ""
        databaseDescriptionChangedTime = Date.now
        defaultUserName = ""
        defaultUserNameChangedTime = Date.now
        maintenanceHistoryDays = Meta2.defaultMaintenanceHistoryDays
        colorString = ""
        masterKeyChangedTime = Date.now
        masterKeyChangeRec = Int64(-1)
        masterKeyChangeForce = Int64(-1)
        memoryProtection = MemoryProtection()
        isRecycleBinEnabled = true
        recycleBinGroupUUID = UUID.ZERO
        recycleBinChangedTime = Date.now
        entryTemplatesGroupUUID = UUID.ZERO
        entryTemplatesGroupChangedTime = Date.now
        historyMaxItems = Meta2.defaultHistoryMaxItems
        historyMaxSize = Meta2.defaultHistoryMaxSize
        lastSelectedGroupUUID = UUID.ZERO
        lastTopVisibleGroupUUID = UUID.ZERO
        customData = CustomData2()
        customIcons = [:]
    }
    deinit {
        erase()
    }
    
    func erase() {
        generator.erase()
        headerHash?.erase()
        settingsChangedTime = Date.now
        databaseName.erase()
        databaseNameChangedTime = Date.now
        databaseDescription.erase()
        databaseDescriptionChangedTime = Date.now
        defaultUserName.erase()
        defaultUserNameChangedTime = Date.now
        maintenanceHistoryDays = Meta2.defaultMaintenanceHistoryDays
        colorString.erase()
        masterKeyChangedTime = Date.now
        masterKeyChangeRec = Int64(-1)
        masterKeyChangeForce = Int64(-1)
        memoryProtection.erase()
        isRecycleBinEnabled = true
        recycleBinGroupUUID.erase()
        recycleBinChangedTime = Date.now
        entryTemplatesGroupUUID.erase()
        entryTemplatesGroupChangedTime = Date.now
        historyMaxItems = Meta2.defaultHistoryMaxItems
        historyMaxSize = Meta2.defaultHistoryMaxSize
        lastSelectedGroupUUID.erase()
        lastTopVisibleGroupUUID.erase()
        customData.erase()
        customIcons.removeAll() //erase()
    }
    
    /// - Throws: Xml2.ParsingError, ProgressInterruption
    func load(xml: AEXMLElement, streamCipher: StreamCipher) throws  {
        assert(xml.name == Xml2.meta)
        Diag.verbose("Loading XML: meta")
        erase()
        
        let formatVersion = database.header.formatVersion
        for tag in xml.children {
            switch tag.name {
            case Xml2.generator:
                self.generator = tag.value ?? ""
                Diag.info("Database was last edited by: \(generator)")
            case Xml2.settingsChanged: // v4 only
                guard formatVersion == .v4 else {
                    Diag.error("Found \(tag.name) tag in non-V4 database")
                    throw Xml2.ParsingError.unexpectedTag(actual: tag.name, expected: nil)
                }
                self.settingsChangedTime = database.xmlStringToDate(tag.value) ?? Date.now
            case Xml2.headerHash: // v3 only
                guard formatVersion == .v3 else {
                    Diag.error("Found \(tag.name) tag in non-V3 database")
                    throw Xml2.ParsingError.unexpectedTag(actual: tag.name, expected: nil)
                }
                self.headerHash = ByteArray(base64Encoded: tag.value) // ok if nil
            case Xml2.databaseName:
                self.databaseName = tag.value ?? ""
            case Xml2.databaseNameChanged:
                self.databaseNameChangedTime = database.xmlStringToDate(tag.value) ?? Date.now
            case Xml2.databaseDescription:
                self.databaseDescription = tag.value ?? ""
            case Xml2.databaseDescriptionChanged:
                self.databaseDescriptionChangedTime =
                    database.xmlStringToDate(tag.value) ?? Date.now
            case Xml2.defaultUserName:
                self.defaultUserName = tag.value ?? ""
            case Xml2.defaultUserNameChanged:
                self.defaultUserNameChangedTime = database.xmlStringToDate(tag.value) ?? Date.now
            case Xml2.maintenanceHistoryDays:
                self.maintenanceHistoryDays =
                    UInt32(tag.value) ?? Meta2.defaultMaintenanceHistoryDays
            case Xml2.color:
                self.colorString = tag.value ?? ""
            case Xml2.masterKeyChanged:
                self.masterKeyChangedTime = database.xmlStringToDate(tag.value) ?? Date.now
            case Xml2.masterKeyChangeRec:
                self.masterKeyChangeRec = Int64(tag.value) ?? -1
            case Xml2.masterKeyChangeForce:
                self.masterKeyChangeForce = Int64(tag.value) ?? -1
            case Xml2.memoryProtection:
                try memoryProtection.load(xml: tag)
                Diag.verbose("Memory protection loaded OK")
            case Xml2.customIcons:
                try loadCustomIcons(xml: tag)
                Diag.verbose("Custom icons loaded OK [count: \(customIcons.count)]")
            case Xml2.recycleBinEnabled:
                self.isRecycleBinEnabled = Bool(string: tag.value)
            case Xml2.recycleBinUUID:
                self.recycleBinGroupUUID = UUID(base64Encoded: tag.value) ?? UUID.ZERO
            case Xml2.recycleBinChanged:
                self.recycleBinChangedTime = database.xmlStringToDate(tag.value) ?? Date.now
            case Xml2.entryTemplatesGroup:
                self.entryTemplatesGroupUUID = UUID(base64Encoded: tag.value) ?? UUID.ZERO
            case Xml2.entryTemplatesGroupChanged:
                self.entryTemplatesGroupChangedTime =
                    database.xmlStringToDate(tag.value) ?? Date.now
            case Xml2.historyMaxItems:
                self.historyMaxItems = Int32(tag.value) ?? -1
            case Xml2.historyMaxSize:
                self.historyMaxSize = Int64(tag.value) ?? -1
            case Xml2.lastSelectedGroup:
                self.lastSelectedGroupUUID = UUID(base64Encoded: tag.value) ?? UUID.ZERO
            case Xml2.lastTopVisibleGroup:
                self.lastTopVisibleGroupUUID = UUID(base64Encoded: tag.value) ?? UUID.ZERO
            case Xml2.binaries:
                try loadBinaries(xml: tag, streamCipher: streamCipher)
                    // throws Xml2.ParsingError, ProgressInterruption
                Diag.verbose("Binaries loaded OK [count: \(database.binaries.count)]")
            case Xml2.customData:
                try customData.load(xml: tag, streamCipher: streamCipher, xmlParentName: "Meta")
                Diag.verbose("Custom data loaded OK [count: \(customData.count)]")
            default:
                Diag.error("Unexpected XML tag in Meta: \(tag.name)")
                throw Xml2.ParsingError.unexpectedTag(actual: tag.name, expected: "Meta/*")
            }
        }
    }
    
    /// - Throws: Xml2.ParsingError
    func loadCustomIcons(xml: AEXMLElement) throws {
        assert(xml.name == Xml2.customIcons)
        Diag.verbose("Loading XML: custom icons")
        for tag in xml.children {
            switch tag.name {
            case Xml2.icon:
                let icon = CustomIcon2()
                try icon.load(xml: tag) // throws Xml2.ParsingError
                customIcons[icon.uuid] = icon
                Diag.verbose("Custom icon loaded OK")
            default:
                Diag.error("Unexpected XML tag in Meta/CustomIcons: \(tag.name)")
                throw Xml2.ParsingError.unexpectedTag(
                    actual: tag.name,
                    expected: "Meta/CustomIcons/*")
            }
        }
    }
    
    /// - Throws: Xml2.ParsingError, ProgressInterruption
    func loadBinaries(xml: AEXMLElement, streamCipher: StreamCipher) throws {
        assert(xml.name == Xml2.binaries)
        Diag.verbose("Loading XML: meta binaries")
        database.binaries.removeAll()
        for tag in xml.children {
            switch tag.name {
            case Xml2.binary:
                let binary = Binary2()
                try binary.load(xml: tag, streamCipher: streamCipher)
                    // throws Xml2.ParsingError, ProgressInterruption
                database.binaries.append(binary)
                Diag.verbose("Binary loaded OK")
            default:
                Diag.error("Unexpected XML tag in Meta/Binaries: \(tag.name)")
                throw Xml2.ParsingError.unexpectedTag(actual: tag.name, expected: "Meta/Binaries/*")
            }
        }
    }

    /// Creates a Recycle Bin group and registers it in this `Meta`.
    /// (But does NOT add it into group tree)
    /// If one already exists, throws an assertion failure.
    ///
    /// - Returns: initialized group instance.
    func createRecycleBinGroup() -> Group2 {
        assert(recycleBinGroupUUID == UUID.ZERO)
        
        let backupGroup = Group2(database: database)
        backupGroup.uuid = UUID()
        backupGroup.name = NSLocalizedString("Recycle Bin", comment: "Name of a group which contains deleted entries")
        backupGroup.iconID = IconID.trashBin
        backupGroup.isDeleted = true

        self.recycleBinGroupUUID = backupGroup.uuid
        self.recycleBinChangedTime = Date.now
        
        return backupGroup
    }
    
    /// - Throws: `ProgressInterruption`
    func toXml(streamCipher: StreamCipher) throws -> AEXMLElement {
        Diag.verbose("Generating XML: meta")
        let xmlMeta = AEXMLElement(name: Xml2.meta)
        // Replace the original generator name with this app's name
        xmlMeta.addChild(name: Xml2.generator, value: Meta2.generatorName)
        
        let formatVersion = database.header.formatVersion
        switch formatVersion {
        case .v3:
            if let headerHash = headerHash {
                xmlMeta.addChild(name: Xml2.headerHash, value: headerHash.base64EncodedString())
                //print("Meta2.toXml: headerHash: \(headerHash.asHexString)")
            }
        case .v4:
            xmlMeta.addChild(
                name: Xml2.settingsChanged,
                value: settingsChangedTime.base64EncodedString())
        }
        xmlMeta.addChild(
            name: Xml2.databaseName,
            value: databaseName)
        xmlMeta.addChild(
            name: Xml2.databaseNameChanged,
            value: database.xmlDateToString(databaseNameChangedTime))
        xmlMeta.addChild(
            name: Xml2.databaseDescription,
            value: databaseDescription)
        xmlMeta.addChild(
            name: Xml2.databaseDescriptionChanged,
            value: database.xmlDateToString(databaseDescriptionChangedTime))
        xmlMeta.addChild(
            name: Xml2.defaultUserName,
            value: defaultUserName)
        xmlMeta.addChild(
            name: Xml2.defaultUserNameChanged,
            value: database.xmlDateToString(defaultUserNameChangedTime))
        xmlMeta.addChild(
            name: Xml2.maintenanceHistoryDays,
            value: String(maintenanceHistoryDays))
        xmlMeta.addChild(
            name: Xml2.color,
            value: colorString)
        xmlMeta.addChild(
            name: Xml2.masterKeyChanged,
            value: database.xmlDateToString(masterKeyChangedTime))
        xmlMeta.addChild(
            name: Xml2.masterKeyChangeRec,
            value: String(masterKeyChangeRec))
        xmlMeta.addChild(
            name: Xml2.masterKeyChangeForce,
            value: String(masterKeyChangeForce))
        xmlMeta.addChild(memoryProtection.toXml())
        xmlMeta.addChild(
            name: Xml2.recycleBinEnabled,
            value: isRecycleBinEnabled ? Xml2._true : Xml2._false)
        xmlMeta.addChild(
            name: Xml2.recycleBinUUID,
            value: recycleBinGroupUUID.base64EncodedString())
        xmlMeta.addChild(
            name: Xml2.recycleBinChanged,
            value: database.xmlDateToString(recycleBinChangedTime))
        xmlMeta.addChild(
            name: Xml2.entryTemplatesGroup,
            value: entryTemplatesGroupUUID.base64EncodedString())
        xmlMeta.addChild(
            name: Xml2.entryTemplatesGroupChanged,
            value: database.xmlDateToString(entryTemplatesGroupChangedTime))
        xmlMeta.addChild(
            name: Xml2.historyMaxItems,
            value: String(historyMaxItems))
        xmlMeta.addChild(
            name: Xml2.historyMaxSize,
            value: String(historyMaxSize))
        xmlMeta.addChild(
            name: Xml2.lastSelectedGroup,
            value: lastSelectedGroupUUID.base64EncodedString())
        xmlMeta.addChild(
            name: Xml2.lastTopVisibleGroup,
            value: lastTopVisibleGroupUUID.base64EncodedString())
        
        if let xmlCustomIcons = customIconsToXml() {
            xmlMeta.addChild(xmlCustomIcons)
        }
        if formatVersion == .v3 {
            // v3 stores binaries in meta XML.
            // v4 stores them in the inner header instead.
            if let xmlBinaries = try binariesToXml(streamCipher: streamCipher)
                // throws ProgressInterruption
            {
                xmlMeta.addChild(xmlBinaries)
            }
            Diag.verbose("Binaries XML generated OK")
        }
        xmlMeta.addChild(customData.toXml())
        return xmlMeta
    }

    /// - Returns: `customIcons` as an XML element, or nil if there are no icons
    internal func customIconsToXml() -> AEXMLElement? {
        if customIcons.isEmpty {
            return nil
        } else {
            let xmlCustomIcons = AEXMLElement(name: Xml2.customIcons)
            for customIcon in customIcons.values {
                xmlCustomIcons.addChild(customIcon.toXml())
            }
            return xmlCustomIcons
        }
    }
    
    /// - Returns: `binaries` as an XML element, or nil if there are no binaries
    /// - Throws: `ProgressInterruption`
    internal func binariesToXml(streamCipher: StreamCipher) throws -> AEXMLElement? {
        if database.binaries.isEmpty {
            Diag.verbose("No binaries in Meta")
            return nil
        } else {
            Diag.verbose("Generating XML: meta binaries")
            let xmlBinaries = AEXMLElement(name: Xml2.binaries)
            for binary in database.binaries {
                xmlBinaries.addChild(try binary.toXml(streamCipher: streamCipher))
                    // throws ProgressInterruption
            }
            return xmlBinaries
        }
    }
    
    /// Sets all meta timestamps to given time.
    /// Use for initialization of a newly created database.
    func setAllTimestamps(to time: Date) {
        settingsChangedTime = time
        databaseNameChangedTime = time
        databaseDescriptionChangedTime = time
        defaultUserNameChangedTime = time
        masterKeyChangedTime = time
        recycleBinChangedTime = time
        entryTemplatesGroupChangedTime = time
    }
}