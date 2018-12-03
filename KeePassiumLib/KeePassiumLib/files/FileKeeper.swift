//
//  FileKeeper.swift
//  KeePassium
//
//  Created by Andrei Popleteev on 2018-08-19.
//  Copyright © 2018 Andrei Popleteev. All rights reserved.
//

import UIKit

public enum FileKeeperError: LocalizedError {
    case openError(reason: String)
    case importError(reason: String)
    case removalError(reason: String)
    public var errorDescription: String? {
        switch self {
        case .openError(let reason):
            return NSLocalizedString("Failed to open file. Reason: \(reason)", comment: "Error message")
        case .importError(let reason):
            return NSLocalizedString("File import error. Reason: \(reason)", comment: "Error message")
        case .removalError(let reason):
            return NSLocalizedString("Failed to remove file. Reason: \(reason)", comment: "Error message")
        }
    }
}

public class FileKeeper {
    public static let shared = FileKeeper()
    
    private enum UserDefaultsKey {
        static let prefix = "com.keepassium.recentFiles"
        static let internalDatabases = prefix + ".internal.databases"
        static let internalKeyFiles = prefix + ".internal.keyFiles"
        static let externalDatabases = prefix + ".external.databases"
        static let externalKeyFiles = prefix + ".external.keyFiles"
    }
    
    private static let documentsDirectoryName = "Documents"
    private static let inboxDirectoryName = "Inbox"
    private static let backupDirectoryName = "Backup"
    
    public enum OpenMode {
        case openInPlace
        case `import`
    }
    
    /// URL to be opened/imported
    private var urlToOpen: URL?
    /// How `urlToOpen` should be treated.
    private var openMode: OpenMode = .openInPlace
    /// Ensures thread safety of delayed file operations
    private var pendingOperationGroup = DispatchGroup()
    
    /// App sandbox Documents folder
    private let docDirURL: URL
    /// App group's shared Backup folder
    private let backupDirURL: URL
    
    // True when there are files to be opened/imported.
    public var hasPendingFileOperations: Bool {
        return urlToOpen != nil
    }

    private init() {
        docDirURL = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask).first!

        print("\nDoc dir: \(docDirURL)\n")
        
        // Intitialize (and create if necessary) internal directories.
        guard let sharedContainerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.id) else { fatalError() }
        backupDirURL = sharedContainerURL
            .appendingPathComponent(FileKeeper.backupDirectoryName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: backupDirURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            Diag.warning("Failed to create backup directory")
            // No further action: postponing the error until the first file writing operation
            // that has UI to show the error to the user.
        }
    }

    /// Returns URL of an internal directory corresponding to given location.
    /// Non-nil value guaranteed only for internal locations; for external ones returns `nil`.
    fileprivate func getDirectory(for location: URLReference.Location) -> URL? {
        switch location {
        case .internalDocuments:
            return docDirURL
        case .internalBackup:
            return backupDirURL
        case .internalInbox:
            return docDirURL.appendingPathComponent(
                FileKeeper.inboxDirectoryName, isDirectory: true)
        default:
            return nil
        }
    }
    
    /// Returns the location type corresponding to given url.
    /// (Defaults to `.external` when does not match any internal location.)
    public func getLocation(for filePath: URL) -> URLReference.Location {
        let filePath = filePath.standardizedFileURL.deletingLastPathComponent().path
        for candidateLocation in URLReference.Location.allInternal {
            let dirPath = getDirectory(for: candidateLocation)!.path
            if filePath == dirPath {
                return candidateLocation
            }
        }
        return .external
    }
    
    private func userDefaultsKey(for fileType: FileType, external isExternal: Bool) -> String {
        switch fileType {
        case .database:
            if isExternal {
                return UserDefaultsKey.externalDatabases
            } else {
                return UserDefaultsKey.internalDatabases
            }
        case .keyFile:
            if isExternal {
                return UserDefaultsKey.externalKeyFiles
            } else {
                return UserDefaultsKey.internalKeyFiles
            }
        }
    }
    /// Returns URL references stored in user defaults.
    private func getStoredReferences(
        fileType: FileType,
        forExternalFiles isExternal: Bool
        ) -> [URLReference]
    {
        let key = userDefaultsKey(for: fileType, external: isExternal)
        guard let refsData = UserDefaults.appGroupShared.array(forKey: key) else {
            return []
        }
        var refs: [URLReference] = []
        for data in refsData {
            if let ref = URLReference.deserialize(from: data as! Data) {
                refs.append(ref)
            }
        }
        return refs
    }
    
    /// Stores given URL references in user defaults.
    private func storeReferences(
        _ refs: [URLReference],
        fileType: FileType,
        forExternalFiles isExternal: Bool)
    {
        let serializedRefs = refs.map{ $0.serialize() }
        let key = userDefaultsKey(for: fileType, external: isExternal)
        UserDefaults.appGroupShared.set(serializedRefs, forKey: key)
    }

    /// Returns the stored reference for the given URL, if such reference exists.
    private func findStoredExternalReferenceFor(url: URL, fileType: FileType) -> URLReference? {
        let storedRefs = getStoredReferences(fileType: fileType, forExternalFiles: true)
        for ref in storedRefs {
            if let refUrl = try? ref.resolve(), refUrl == url {
                return ref
            }
        }
        return nil
    }

    /// For local files in ~/Documents/**/*, removes the file.
    /// - Throws: `FileKeeperError`
    public func deleteFile(_ urlRef: URLReference, fileType: FileType, ignoreErrors: Bool) throws {
        Diag.debug("Will trash local file [fileType: \(fileType)]")
        do {
            let url = try urlRef.resolve()
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            FileKeeperNotifier.notifyFileRemoved(urlRef: urlRef, fileType: fileType)
            Diag.info("Local file moved to trash")
        } catch {
            if ignoreErrors {
                Diag.debug("Suppressed file deletion error [message: '\(error.localizedDescription)']")
            } else {
                Diag.error("Failed to delete file [message: '\(error.localizedDescription)']")
                throw FileKeeperError.removalError(reason: error.localizedDescription)
            }
        }

    }
    
    /// Removes reference to an external file from user defaults (keeps the file).
    /// If no such reference, still silently returns.
    public func removeExternalReference(_ urlRef: URLReference, fileType: FileType) {
        Diag.debug("Removing URL reference [fileType: \(fileType)]")
        var refs = getStoredReferences(fileType: fileType, forExternalFiles: true)
        if let index = refs.index(of: urlRef) {
            refs.remove(at: index)
            storeReferences(refs, fileType: fileType, forExternalFiles: true)
            FileKeeperNotifier.notifyFileRemoved(urlRef: urlRef, fileType: fileType)
            Diag.info("URL reference removed successfully")
        } else {
            assertionFailure("Tried to delete non-existent reference")
            Diag.warning("Failed to remove URL reference - no such reference")
        }
    }
    
    /// Returns references to both local and external files.
    public func getAllReferences(fileType: FileType, includeBackup: Bool) -> [URLReference] {
        var result: [URLReference] = []
//        result.append(contentsOf:
//            scanLocalDirectory(fileType: fileType, location: .internalDocuments))
        result.append(contentsOf:getStoredReferences(fileType: fileType, forExternalFiles: true))
        if AppGroup.isMainApp {
            let sandboxFileRefs = scanLocalDirectory(
                fileType: fileType, location: .internalDocuments)
            // store app's sandboxed file refs for the app extension
            storeReferences(sandboxFileRefs, fileType: fileType, forExternalFiles: false)
            result.append(contentsOf: sandboxFileRefs)
        } else {
            // App extension has no access to app sandbox,
            // so we use pre-saved references to sandbox contents instead.
            result.append(contentsOf:
                getStoredReferences(fileType: fileType, forExternalFiles: false))
        }

        if includeBackup {
            result.append(contentsOf:
                scanLocalDirectory(fileType: fileType, location: .internalBackup))
        }
        return result
    }
    
    /// Returns all files in directory specified by `location`.
    /// Performs shallow search, does not follow deeper directories.
    func scanLocalDirectory(fileType: FileType, location: URLReference.Location) -> [URLReference] {
        var refs: [URLReference] = []
        
        let dirURL = getDirectory(for: location)! // will crash for external location
        do {
            let dirContents = try FileManager.default.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: nil,
                options: [])
            for url in dirContents {
                if !url.isDirectory && FileType(for: url) == fileType {
                    let urlRef = try URLReference(from: url, location: location)
                    refs.append(urlRef)
                }
            }
        } catch {
            Diag.error(error.localizedDescription)
        }
        return refs
    }
    
    /// Stores the `url` to be added (opened or imported) as a file at some later point.
    public func prepareToAddFile(url: URL, mode: OpenMode) {
        assert(AppGroup.isMainApp, "App extension should not be importing files")
        Diag.debug("Preparing to add file [mode: \(mode)]")
        self.urlToOpen = url
        self.openMode = mode
        FileKeeperNotifier.notifyPendingFileOperation()
    }
    
    /// Performs prepared file operation (see `prepareToAddFile`) asynchronously.
    public func processPendingOperations(
        success successHandler: ((URLReference)->Void)?,
        error errorHandler: ((FileKeeperError)->Void)?)
    {
        pendingOperationGroup.wait()
        pendingOperationGroup.enter()
        defer { pendingOperationGroup.leave() }
        
        guard let sourceURL = urlToOpen else { return }
        urlToOpen = nil

        assert(AppGroup.isMainApp, "App extension should not be importing files")
        Diag.debug("Will process pending file operations")

        guard sourceURL.isFileURL else {
            Diag.error("Tried to import a non-file URL: \(sourceURL.redacted)")
            let messageNotAFileURL = NSLocalizedString("Not a file URL", comment: "Error message: tried to import URL which does not point to a file")
            switch openMode {
            case .import:
                let importError = FileKeeperError.importError(reason: messageNotAFileURL)
                errorHandler?(importError)
                return
            case .openInPlace:
                let openError = FileKeeperError.openError(reason: messageNotAFileURL)
                errorHandler?(openError)
                return
            }
        }
        
        // General plan of action:
        // External files:
        //  - Key file: import
        //  - Database: open in place, or import (if shared from external app via Copy to KeePassium)
        // Internal files:
        //    /Inbox: import (key file and database)
        //    /Backup: open in place
        //    /Documents: open in place
        
        let fileType = FileType(for: sourceURL)
        let location = getLocation(for: sourceURL)
        switch location {
        case .external:
            // key file: import, database: open in place
            processExternalFile(
                url: sourceURL,
                fileType: fileType,
                success: successHandler,
                error: errorHandler)
        case .internalDocuments, .internalBackup:
            // we already have the file: open in place
            processInternalFile(
                url: sourceURL,
                fileType: fileType,
                location: location,
                success: successHandler,
                error: errorHandler)
        case .internalInbox:
            processInboxFile(
                url: sourceURL,
                fileType: fileType,
                location: location,
                success: successHandler,
                error: errorHandler)
        }
    }
    
    /// Performs addition of an external file.
    /// Key files are copied to Documents.
    /// Database files are added as URL references.
    private func processExternalFile(
        url sourceURL: URL,
        fileType: FileType,
        success successHandler: ((URLReference) -> Void)?,
        error errorHandler: ((FileKeeperError) -> Void)?)
    {
        switch fileType {
        case .database:
            if let urlRef = findStoredExternalReferenceFor(url: sourceURL, fileType: fileType) {
                Settings.current.startupDatabase = urlRef
                FileKeeperNotifier.notifyFileAdded(urlRef: urlRef, fileType: fileType)
                Diag.info("Added already known external file, deduplicating.")
                successHandler?(urlRef)
                return
            }
            addExternalFileRef(url: sourceURL, fileType: fileType, success: { urlRef in
                Settings.current.startupDatabase = urlRef
                FileKeeperNotifier.notifyFileAdded(urlRef: urlRef, fileType: fileType)
                Diag.info("External database added successfully")
                successHandler?(urlRef)
            }, error: errorHandler)
        case .keyFile:
            importFile(url: sourceURL, success: { url in
                do {
                    let urlRef = try URLReference(
                        from: url,
                        location: self.getLocation(for: url))
                    FileKeeperNotifier.notifyFileAdded(urlRef: urlRef, fileType: fileType)
                    Diag.info("External key file imported successfully")
                    successHandler?(urlRef)
                } catch {
                    Diag.error("""
                        Failed to import external file [
                            type: \(fileType),
                            message: \(error.localizedDescription),
                            url: \(sourceURL.redacted)]
                        """)
                    let importError = FileKeeperError.importError(reason: error.localizedDescription)
                    errorHandler?(importError)
                }
            }, error: errorHandler)
        }
    }
    
    /// Perform import of a file in Documents/Inbox.
    private func processInboxFile(
        url sourceURL: URL,
        fileType: FileType,
        location: URLReference.Location,
        success successHandler: ((URLReference) -> Void)?,
        error errorHandler: ((FileKeeperError) -> Void)?)
    {
        importFile(url: sourceURL, success: { url in
            do {
                let urlRef = try URLReference(from: url, location: location)
                if fileType == .database {
                    Settings.current.startupDatabase = urlRef
                }
                FileKeeperNotifier.notifyFileAdded(urlRef: urlRef, fileType: fileType)
                Diag.info("Inbox file added successfully [fileType: \(fileType)]")
                successHandler?(urlRef)
            } catch {
                Diag.error("Failed to import inbox file [type: \(fileType), message: \(error.localizedDescription)]")
                let importError = FileKeeperError.importError(reason: error.localizedDescription)
                errorHandler?(importError)
            }
        }, error: errorHandler)
    }
    
    
    /// Handles processing request for an internal file.
    /// Does nothing with the file, but pretends as if it has been imported
    /// (notifies, updates startup database, ...)
    private func processInternalFile(
        url sourceURL: URL,
        fileType: FileType,
        location: URLReference.Location,
        success successHandler: ((URLReference) -> Void)?,
        error errorHandler: ((FileKeeperError) -> Void)?)
    {
        do {
            let urlRef = try URLReference(from: sourceURL, location: location)
            if fileType == .database {
                Settings.current.startupDatabase = urlRef
            }
            FileKeeperNotifier.notifyFileAdded(urlRef: urlRef, fileType: fileType)
            Diag.info("Internal file processed successfully [fileType: \(fileType), location: \(location)]")
            successHandler?(urlRef)
        } catch {
            Diag.error("Failed to create URL reference [error: '\(error.localizedDescription)', url: '\(sourceURL.redacted)']")
            let importError = FileKeeperError.openError(reason: error.localizedDescription)
            errorHandler?(importError)
        }
    }
    
    /// Adds external file as a URL reference.
    private func addExternalFileRef(
        url sourceURL: URL,
        fileType: FileType,
        success successHandler: ((URLReference) -> Void)?,
        error errorHandler: ((FileKeeperError) -> Void)?)
    {
        Diag.debug("Will add external file reference")
        // To access an external URL, we need to init a UIDocument with that URL,
        // and keep the instance around when using the URL.
        // Note: If dummyDoc is replaced with `_`, the document is immediately
        //       deallocated => transient "permission denied" issues.
        let dummyDoc = FileDocument(fileURL: sourceURL)
        do {
            let newRef = try URLReference(from: sourceURL, location: .external) // throws some UIKit error
            
            var storedRefs = getStoredReferences(fileType: fileType, forExternalFiles: true)
            storedRefs.insert(newRef, at: 0)
            storeReferences(storedRefs, fileType: fileType, forExternalFiles: true)
            
            dummyDoc.data.erase() // just to silence the "unused var" warning; `data` is empty anyway.
            Diag.info("External URL reference added OK")
            successHandler?(newRef)
        } catch {
            Diag.error("Failed to create URL reference [error: '\(error.localizedDescription)', url: '\(sourceURL.redacted)']")
            let importError = FileKeeperError.openError(reason: error.localizedDescription)
            errorHandler?(importError)
        }
    }
    
    /// Given a file (either external or in 'Documents/Inbox'), copes/moves it to 'Documents'.
    private func importFile(
        url sourceURL: URL,
        success successHandler: ((URL) -> Void)?,
        error errorHandler: ((FileKeeperError)->Void)?)
    {
        let docDirURL = getDirectory(for: .internalDocuments)!
        let inboxDirURL = getDirectory(for: .internalInbox)!
        let fileName = sourceURL.lastPathComponent
        let targetURL = docDirURL.appendingPathComponent(fileName)
        let sourceDirs = sourceURL.deletingLastPathComponent() // without file name
        
        if sourceDirs.path == docDirURL.path {
            Diag.info("Tried to import a file already in Documents, nothing to do")
            successHandler?(sourceURL)
            return
        }
        
        if sourceDirs.path == inboxDirURL.path {
            importInboxFile(
                from: sourceURL,
                to: targetURL,
                success: successHandler,
                error: errorHandler)
        } else {
            importExternalFile(
                from: sourceURL,
                to: targetURL,
                success: successHandler,
                error: errorHandler)
        }
    }
    
    /// Moves a file from Documents/Inbox to Documents.
    /// Parameters are not checked.
    private func importInboxFile(
        from sourceURL: URL,
        to targetURL: URL,
        success successHandler: ((URL) -> Void)?,
        error errorHandler: ((FileKeeperError)->Void)?)
    {
        Diag.debug("Will import file from Inbox")
        let movedURL: URL?
        do {
            defer { clearInbox() }
            movedURL = try FileManager.default.replaceItemAt(targetURL, withItemAt: sourceURL)
        } catch {
            Diag.error("Failed to import [reason: \(error.localizedDescription)]")
            let importError = FileKeeperError.importError(reason: error.localizedDescription)
            errorHandler?(importError)
            return
        }
        
        guard let finalURL = movedURL else {
            Diag.error("Failed to replace file. Final URL is nil.")
            let importError =
                FileKeeperError.importError(reason: "Failed to replace file. Final URL is nil.")
            errorHandler?(importError)
            return
        }
        successHandler?(finalURL)
    }
    
    /// Copies an external file to Documents.
    /// Parameters are not checked.
    private func importExternalFile(
        from sourceURL: URL,
        to targetURL: URL,
        success successHandler: ((URL) -> Void)?,
        error errorHandler: ((FileKeeperError)->Void)?)
    {
        Diag.debug("Will import external file")
        let doc = FileDocument(fileURL: sourceURL)
        doc.open(successHandler: {
            do {
                try doc.data.write(to: targetURL, options: [.withoutOverwriting])
                Diag.info("External file copied successfully")
                successHandler?(targetURL)
            } catch {
                Diag.error("Failed to save external file [message: \(error.localizedDescription)]")
                let importError = FileKeeperError.importError(reason: error.localizedDescription)
                errorHandler?(importError)
            }
        }, errorHandler: { error in
            Diag.error("Failed to import external file [message: \(error.localizedDescription)]")
            let importError = FileKeeperError.importError(reason: error.localizedDescription)
            errorHandler?(importError)
        })
    }
    
    
    /// Removes all files from Documents/Inbox.
    /// Silently ignores any errors.
    private func clearInbox() {
        let inboxDir = getDirectory(for: .internalInbox)!
        guard let inboxFiles = try? FileManager.default
            .contentsOfDirectory(at: inboxDir, includingPropertiesForKeys: nil, options: []) else
        {
            // probably, there is no Inbox there
            return
        }
        for url in inboxFiles {
            try? FileManager.default.removeItem(at: url) // ignoring any errors
        }
    }
    
    /// Saves `contents` in a timestamped file in local Documents/Backup folder.
    ///
    /// - Parameters:
    ///     - nameTemplate: template file name (e.g. "filename.ext")
    ///     - contents: bytes to store
    /// - Throws: nothing, any errors are silently ignored.
    func makeBackup(nameTemplate: String, contents: ByteArray) {
        guard let encodedNameTemplate = nameTemplate
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        guard let nameTemplateURL = URL(string: encodedNameTemplate) else { return }
        
        let fileManager = FileManager.default
        do {
            let backupDirURL = getDirectory(for: .internalBackup)!
            try fileManager.createDirectory(
                at: backupDirURL,
                withIntermediateDirectories: true,
                attributes: nil)

            // We deduct one second from the timestamp to ensure
            // correct timing order of backup vs. original files
            let timestamp = Date.now - 1.0
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
            let timestampStr = dateFormatter.string(from: timestamp)

            let baseFileName = nameTemplateURL
                .deletingPathExtension()
                .absoluteString
                .removingPercentEncoding  // should be OK, but if failed - fallback to
                ?? nameTemplate           // original template, even with extension
            let baseFileExt = nameTemplateURL.pathExtension
            let backupFileURL = backupDirURL
                .appendingPathComponent(baseFileName + "_" + timestampStr, isDirectory: false)
                .appendingPathExtension(baseFileExt)
            try contents.asData.write(to: backupFileURL, options: .atomic)
            
            // set file timestamps
            try fileManager.setAttributes(
                [FileAttributeKey.creationDate: timestamp,
                 FileAttributeKey.modificationDate: timestamp],
                ofItemAtPath: backupFileURL.path)
            Diag.info("Backup copy created OK")
        } catch {
            Diag.warning("Failed to make backup copy [error: \(error.localizedDescription)]")
            // no further action, simply return
        }
    }
}