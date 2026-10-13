import CryptoKit
import Foundation
import Security
import Testing

struct CryptoTests {
    private func parts(_ token: String) throws -> (header: [String: Any], payload: [String: Any], signingInput: String, signature: Data) {
        let segments = token.split(separator: ".").map(String.init)
        try #require(segments.count == 3)
        let header = try JSONSerialization.jsonObject(with: try #require(JWT.base64URLDecoded(segments[0]))) as? [String: Any]
        let payload = try JSONSerialization.jsonObject(with: try #require(JWT.base64URLDecoded(segments[1]))) as? [String: Any]
        return (try #require(header), try #require(payload), segments[0] + "." + segments[1], try #require(JWT.base64URLDecoded(segments[2])))
    }

    @Test func appStoreConnectTokenIsAValidES256Signature() throws {
        let key = P256.Signing.PrivateKey()
        let now = Date(timeIntervalSince1970: 1_791_900_000)
        let token = try JWT.appStoreConnectToken(issuerID: "issuer-1", keyID: "KEY1234567", privateKeyPEM: key.pemRepresentation, now: now)
        let jwt = try parts(token)

        #expect(jwt.header["alg"] as? String == "ES256")
        #expect(jwt.header["kid"] as? String == "KEY1234567")
        #expect(jwt.payload["iss"] as? String == "issuer-1")
        #expect(jwt.payload["aud"] as? String == "appstoreconnect-v1")
        #expect(jwt.payload["iat"] as? Int == 1_791_900_000)
        #expect(jwt.payload["exp"] as? Int == 1_791_900_900)

        let signature = try P256.Signing.ECDSASignature(rawRepresentation: jwt.signature)
        #expect(key.publicKey.isValidSignature(signature, for: Data(jwt.signingInput.utf8)))
    }

    @Test func rejectsInvalidAppStoreConnectKeys() {
        #expect(throws: BinnacleError.self) { try AppStoreConnectCredentials.validatePrivateKey("not a key") }
        #expect(throws: BinnacleError.self) {
            try JWT.appStoreConnectToken(issuerID: "i", keyID: "k", privateKeyPEM: Fixtures.testRSAPrivateKeyPEM)
        }
    }

    @Test func readsKeyIDFromDownloadedFileName() {
        #expect(AppStoreConnectCredentials.keyID(fromFileName: "AuthKey_ABC123DEFG.p8") == "ABC123DEFG")
        #expect(AppStoreConnectCredentials.keyID(fromFileName: "key.p8") == nil)
    }

    @Test func loadsPKCS8RSAKeys() throws {
        let key = try RSASigner.privateKey(fromPEM: Fixtures.testRSAPrivateKeyPEM)
        #expect(SecKeyGetBlockSize(key) == 256)
        #expect(throws: BinnacleError.self) { try RSASigner.privateKey(fromPEM: "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----") }
    }

    @Test func googleAssertionIsAValidRS256Signature() throws {
        let account = GoogleServiceAccount(
            type: "service_account", projectID: "demo", privateKeyID: "kid-1",
            privateKey: Fixtures.testRSAPrivateKeyPEM, clientEmail: "binnacle@demo.iam.gserviceaccount.com", tokenURI: nil)
        let now = Date(timeIntervalSince1970: 1_791_900_000)
        let jwt = try parts(JWT.googleAssertion(account: account, scopes: GoogleScope.all, now: now))

        #expect(jwt.header["alg"] as? String == "RS256")
        #expect(jwt.header["kid"] as? String == "kid-1")
        #expect(jwt.payload["iss"] as? String == "binnacle@demo.iam.gserviceaccount.com")
        #expect(jwt.payload["aud"] as? String == GoogleEndpoints.token)
        #expect(jwt.payload["scope"] as? String == GoogleScope.all.joined(separator: " "))
        #expect(jwt.payload["exp"] as? Int == 1_791_903_600)

        let publicKey = try #require(SecKeyCopyPublicKey(try RSASigner.privateKey(fromPEM: account.privateKey)))
        let valid = SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256,
                                          Data(jwt.signingInput.utf8) as CFData, jwt.signature as CFData, nil)
        #expect(valid)
    }

    @Test func validatesServiceAccountFiles() throws {
        let valid = try JSONCoding.string(GoogleServiceAccount(
            type: "service_account", projectID: "demo", privateKeyID: "kid",
            privateKey: Fixtures.testRSAPrivateKeyPEM, clientEmail: "a@demo.iam.gserviceaccount.com", tokenURI: GoogleEndpoints.token))
        #expect(try GoogleServiceAccount.parse(valid).projectID == "demo")
        #expect(throws: BinnacleError.self) { try GoogleServiceAccount.parse("{\"type\":\"authorized_user\"}") }
        #expect(throws: BinnacleError.self) { try GoogleServiceAccount.parse("{}") }
    }
}
