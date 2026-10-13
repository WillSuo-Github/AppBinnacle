import CryptoKit
import Foundation
import Security

enum JWT {
    struct Header: Encodable {
        var alg: String
        var kid: String?
        var typ = "JWT"
    }

    struct AppStoreConnectClaims: Encodable {
        var iss: String
        var iat: Int
        var exp: Int
        var aud: String
    }

    struct GoogleClaims: Encodable {
        var iss: String
        var scope: String
        var aud: String
        var iat: Int
        var exp: Int
    }

    /// An ES256 token for the App Store Connect API. Apple accepts lifetimes up to 20 minutes.
    static func appStoreConnectToken(issuerID: String, keyID: String, privateKeyPEM: String,
                                     now: Date = Date(), lifetime: TimeInterval = 15 * 60) throws -> String {
        let key: P256.Signing.PrivateKey
        do {
            key = try P256.Signing.PrivateKey(pemRepresentation: privateKeyPEM)
        } catch {
            throw BinnacleError.invalidCredential("The App Store Connect private key is not a valid .p8 key.")
        }
        let issuedAt = Int(now.timeIntervalSince1970)
        let claims = AppStoreConnectClaims(iss: issuerID, iat: issuedAt, exp: issuedAt + Int(lifetime), aud: "appstoreconnect-v1")
        let signingInput = try segment(Header(alg: "ES256", kid: keyID)) + "." + segment(claims)
        let signature = try key.signature(for: Data(signingInput.utf8))
        return signingInput + "." + base64URLEncoded(signature.rawRepresentation)
    }

    /// An RS256 assertion exchanged for a Google OAuth access token.
    static func googleAssertion(account: GoogleServiceAccount, scopes: [String], now: Date = Date()) throws -> String {
        let issuedAt = Int(now.timeIntervalSince1970)
        let claims = GoogleClaims(
            iss: account.clientEmail,
            scope: scopes.joined(separator: " "),
            aud: account.tokenURI ?? GoogleEndpoints.token,
            iat: issuedAt,
            exp: issuedAt + 3600)
        let signingInput = try segment(Header(alg: "RS256", kid: account.privateKeyID)) + "." + segment(claims)
        let signature = try RSASigner.signSHA256(Data(signingInput.utf8), privateKeyPEM: account.privateKey)
        return signingInput + "." + base64URLEncoded(signature)
    }

    static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64URLDecoded(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        return Data(base64Encoded: base64)
    }

    private static func segment<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return base64URLEncoded(try encoder.encode(value))
    }
}

enum RSASigner {
    static func privateKey(fromPEM pem: String) throws -> SecKey {
        let block = try PEMBlock.decode(pem)
        let pkcs1: Data
        switch block.label {
        case "RSA PRIVATE KEY":
            pkcs1 = block.der
        case "PRIVATE KEY":
            pkcs1 = try PKCS8.rsaPrivateKey(fromPrivateKeyInfo: block.der)
        default:
            throw BinnacleError.invalidCredential("Unsupported private key type \"\(block.label)\".")
        }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, &error) else {
            let reason = error.map { String(describing: $0.takeRetainedValue()) } ?? "unknown error"
            throw BinnacleError.invalidCredential("The RSA private key could not be loaded: \(reason)")
        }
        return key
    }

    static func signSHA256(_ data: Data, privateKeyPEM: String) throws -> Data {
        let key = try privateKey(fromPEM: privateKeyPEM)
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, data as CFData, &error) else {
            let reason = error.map { String(describing: $0.takeRetainedValue()) } ?? "unknown error"
            throw BinnacleError.invalidCredential("Signing with the service account key failed: \(reason)")
        }
        return signature as Data
    }
}

enum PEMBlock {
    static func decode(_ pem: String) throws -> (label: String, der: Data) {
        let lines = pem.split(whereSeparator: \.isNewline).map { $0.trimmed }
        guard let begin = lines.firstIndex(where: { $0.hasPrefix("-----BEGIN ") && $0.hasSuffix("-----") }) else {
            throw BinnacleError.invalidCredential("The key is not in PEM format.")
        }
        let label = String(lines[begin].dropFirst("-----BEGIN ".count).dropLast("-----".count))
        guard let end = lines[(begin + 1)...].firstIndex(of: "-----END \(label)-----"),
              let der = Data(base64Encoded: lines[(begin + 1)..<end].joined()), !der.isEmpty
        else {
            throw BinnacleError.invalidCredential("The PEM key is incomplete.")
        }
        return (label, der)
    }
}

/// Extracts the PKCS#1 RSAPrivateKey that Security.framework expects from a PKCS#8 PrivateKeyInfo.
enum PKCS8 {
    private static let rsaEncryptionOID: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]

    static func rsaPrivateKey(fromPrivateKeyInfo der: Data) throws -> Data {
        var outer = DERReader(der)
        var info = DERReader(try outer.read(tag: 0x30))
        _ = try info.read(tag: 0x02)
        var algorithm = DERReader(try info.read(tag: 0x30))
        guard [UInt8](try algorithm.read(tag: 0x06)) == rsaEncryptionOID else {
            throw BinnacleError.invalidCredential("The private key is not an RSA key.")
        }
        return try info.read(tag: 0x04)
    }
}

struct DERReader {
    private let bytes: [UInt8]
    private var index = 0

    init(_ data: Data) {
        bytes = [UInt8](data)
    }

    mutating func read(tag: UInt8) throws -> Data {
        guard index < bytes.count, bytes[index] == tag else { throw Self.malformed }
        index += 1
        let length = try readLength()
        guard length >= 0, index + length <= bytes.count else { throw Self.malformed }
        defer { index += length }
        return Data(bytes[index..<(index + length)])
    }

    private mutating func readLength() throws -> Int {
        guard index < bytes.count else { throw Self.malformed }
        let first = bytes[index]
        index += 1
        if first & 0x80 == 0 { return Int(first) }
        let count = Int(first & 0x7F)
        guard (1...4).contains(count), index + count <= bytes.count else { throw Self.malformed }
        var length = 0
        for _ in 0..<count {
            length = (length << 8) | Int(bytes[index])
            index += 1
        }
        return length
    }

    private static let malformed = BinnacleError.invalidCredential("The private key is malformed.")
}
