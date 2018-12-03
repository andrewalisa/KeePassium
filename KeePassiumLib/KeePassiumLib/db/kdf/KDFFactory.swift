//
//  KDF.swift
//  KeePassium
//
//  Created by Andrei Popleteev on 2018-03-20.
//  Copyright © 2018 Andrei Popleteev. All rights reserved.
//

import Foundation

/// Protocol for key derivation functions
protocol KeyDerivationFunction {
    /// Predefined UUID of this KDF
    var uuid: UUID { get }
    /// Human-readable KDF name
    var name: String { get }
    /// A `KDFParams` instance prefilled with some reasonable default values
    var defaultParams: KDFParams { get }
    
    /// Returns a fresh instance of key derivation progress
    func initProgress() -> Progress

    init()
    
    /// Performs key transformation using given params.
    /// - Throws: CryptoError, ProgressInterruption
    /// - Returns: resulting key
    func transform(key: SecureByteArray, params: KDFParams) throws -> SecureByteArray
    
    /// Randomize KDF parameters (before saving the DB)
    /// - Throws: CryptoError.rngError
    func randomize(params: inout KDFParams) throws
}

/// Creates a KDF instance by its UUID.
final class KDFFactory {
    private static let argon2kdf = Argon2KDF()
    private static let aeskdf = AESKDF()

    private init() {
        // nothing to do here
    }
    
    /// - Returns: a suitable KDF instance, or `nil` for unknown UUID.
    public static func createFor(uuid: UUID) -> KeyDerivationFunction? {
        switch uuid {
        case argon2kdf.uuid:
            Diag.info("Creating Argon2 KDF")
            return Argon2KDF()
        case aeskdf.uuid:
            Diag.info("Creating AES KDF")
            return AESKDF()
        default:
            Diag.warning("Unrecognized KDF UUID")
            return nil
        }
    }
}