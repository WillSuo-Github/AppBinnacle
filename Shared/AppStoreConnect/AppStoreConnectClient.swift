import Foundation

struct ASCApp: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var bundleID: String
    var sku: String
}

struct CustomerReview: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String
    var rating: Int
    var title: String
    var body: String
    var reviewerNickname: String
    var createdDate: Date
    var territory: String

    /// The review's day in App Store reporting time (Pacific Time).
    var day: Day { Day(date: createdDate, timeZone: .appStoreReporting) }
}

enum SalesReportResponse: Equatable, Sendable {
    case report(String)
    /// Apple answers 404 when a day has no sales or the report is not published yet.
    case noSales
}

struct AppStoreConnectClient: Sendable {
    static let baseURL = URL(string: "https://api.appstoreconnect.apple.com")!
    static let serviceName = "App Store Connect"

    var credentials: AppStoreConnectCredentials
    var transport: any HTTPTransport = URLSessionTransport()

    func apps() async throws -> [ASCApp] {
        var next: URL? = url("/v1/apps", query: [
            URLQueryItem(name: "fields[apps]", value: "name,bundleId,sku"),
            URLQueryItem(name: "limit", value: "200"),
        ])
        var apps: [ASCApp] = []
        var pages = 0
        while let pageURL = next, pages < 20 {
            let document = try await getJSON(ASCDocument<[ASCResource<ASCAppAttributes>]>.self, url: pageURL)
            apps += document.data.map(\.app)
            next = document.links?.next.flatMap { URL(string: $0) }
            pages += 1
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func app(id: String) async throws -> ASCApp {
        let document = try await getJSON(
            ASCDocument<ASCResource<ASCAppAttributes>>.self,
            url: url("/v1/apps/\(id)", query: [URLQueryItem(name: "fields[apps]", value: "name,bundleId,sku")]))
        return document.data.app
    }

    /// The most recent reviews, newest first. One page holds at most 200 reviews.
    func customerReviews(appID: String, limit: Int = 200) async throws -> [CustomerReview] {
        let document = try await getJSON(
            ASCDocument<[ASCResource<ASCReviewAttributes>]>.self,
            url: url("/v1/apps/\(appID)/customerReviews", query: [
                URLQueryItem(name: "sort", value: "-createdDate"),
                URLQueryItem(name: "limit", value: String(min(max(limit, 1), 200))),
                URLQueryItem(name: "fields[customerReviews]", value: "rating,title,body,reviewerNickname,createdDate,territory"),
            ]))
        return document.data.compactMap(\.review)
    }

    /// The daily SALES / SUMMARY report for the whole vendor account.
    func dailySalesReport(vendorNumber: String, day: Day) async throws -> SalesReportResponse {
        let reportURL = url("/v1/salesReports", query: [
            URLQueryItem(name: "filter[frequency]", value: "DAILY"),
            URLQueryItem(name: "filter[reportDate]", value: day.iso),
            URLQueryItem(name: "filter[reportSubType]", value: "SUMMARY"),
            URLQueryItem(name: "filter[reportType]", value: "SALES"),
            URLQueryItem(name: "filter[vendorNumber]", value: vendorNumber),
            URLQueryItem(name: "filter[version]", value: "1_0"),
        ])
        let response = try await send(reportURL, accept: "application/a-gzip")
        if response.statusCode == 404 { return .noSales }
        try Self.check(response)
        let data = Gzip.isGzip(response.data) ? try Gzip.decompress(response.data) : response.data
        return .report(String(decoding: data, as: UTF8.self))
    }

    private func url(_ path: String, query: [URLQueryItem]) -> URL {
        var components = URLComponents(url: Self.baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        return components.url!
    }

    private func getJSON<T: Decodable>(_ type: T.Type, url: URL) async throws -> T {
        let response = try await send(url, accept: "application/json")
        try Self.check(response)
        do {
            return try JSONDecoder().decode(T.self, from: response.data)
        } catch {
            throw BinnacleError.invalidResponse(service: Self.serviceName, message: String(describing: error))
        }
    }

    private func send(_ url: URL, accept: String) async throws -> HTTPResponse {
        let token = try JWT.appStoreConnectToken(
            issuerID: credentials.issuerID, keyID: credentials.keyID, privateKeyPEM: credentials.privateKeyPEM)
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        return try await transport.send(request)
    }

    static func check(_ response: HTTPResponse) throws {
        guard !response.isSuccess else { return }
        var message = errorMessage(from: response.data)
        if response.statusCode == 401 {
            message += (message.isEmpty ? "" : " ") + "Check the issuer ID, key ID, and private key."
        } else if response.statusCode == 403 {
            message += (message.isEmpty ? "" : " ") + "The API key's role may not allow this request."
        }
        throw BinnacleError.http(service: serviceName, status: response.statusCode, message: message)
    }

    static func errorMessage(from data: Data) -> String {
        guard let document = try? JSONDecoder().decode(ASCErrorDocument.self, from: data) else { return "" }
        return document.errors
            .map { [$0.title, $0.detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ": ") }
            .filter { !$0.isEmpty }
            .joined(separator: "; ")
    }
}

private struct ASCDocument<Payload: Decodable>: Decodable {
    struct Links: Decodable { var next: String? }
    var data: Payload
    var links: Links?
}

private struct ASCResource<Attributes: Decodable>: Decodable {
    var id: String
    var attributes: Attributes?
}

private struct ASCAppAttributes: Decodable {
    var name: String?
    var bundleId: String?
    var sku: String?
}

private struct ASCReviewAttributes: Decodable {
    var rating: Int?
    var title: String?
    var body: String?
    var reviewerNickname: String?
    var createdDate: String?
    var territory: String?
}

private struct ASCErrorDocument: Decodable {
    struct Item: Decodable {
        var status: String?
        var code: String?
        var title: String?
        var detail: String?
    }
    var errors: [Item]
}

private extension ASCResource where Attributes == ASCAppAttributes {
    var app: ASCApp {
        ASCApp(id: id, name: attributes?.name ?? "", bundleID: attributes?.bundleId ?? "", sku: attributes?.sku ?? "")
    }
}

private extension ASCResource where Attributes == ASCReviewAttributes {
    var review: CustomerReview? {
        guard let attributes, let rating = attributes.rating,
              let created = attributes.createdDate.flatMap(ISO8601.parse) else { return nil }
        return CustomerReview(
            id: id, rating: rating, title: attributes.title ?? "", body: attributes.body ?? "",
            reviewerNickname: attributes.reviewerNickname ?? "", createdDate: created,
            territory: attributes.territory ?? "")
    }
}
