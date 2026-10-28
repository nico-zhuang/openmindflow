import Foundation
import CoreFoundation

struct ReleaseInfo {
    let version: String
    let pageURL: URL
}

enum ReleaseChannel: String {
    case stable, beta
}

enum ReleaseCheckOutcome {
    case newer(ReleaseInfo)
    case upToDate
    case noPublishedRelease
}

enum ReleaseCheckError: LocalizedError {
    case invalidVersion, invalidResponse, untrustedMetadata, tooLarge, accessRestricted, incompleteListing

    var errorDescription: String? {
        switch self {
        case .invalidVersion: "The installed version is not a canonical numeric X.Y.Z or X.Y.Z-beta.N version."
        case .invalidResponse: "GitHub did not return a valid release response."
        case .untrustedMetadata: "The release page or metadata could not be verified."
        case .tooLarge: "The release response exceeds the 128 KiB metadata limit."
        case .accessRestricted: "GitHub Releases cannot be accessed anonymously. Sign in to GitHub in your browser to view this repository's Releases."
        case .incompleteListing: "GitHub returned 30 Releases; a newer eligible release may be on a later page. Open GitHub Releases in your browser to verify."
        }
    }
}

private struct ReleaseVersion: Comparable {
    let core: [Int]
    let beta: Int?

    init?(_ text: String) {
        let fields = text.split(separator: "-", omittingEmptySubsequences: false)
        guard fields.count == 1 || fields.count == 2 else { return nil }
        let numbers = fields[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3 else { return nil }
        let components = numbers.compactMap(Self.number)
        guard components.count == 3 else { return nil }
        core = components
        if fields.count == 2 {
            guard fields[1].hasPrefix("beta."), let candidate = Self.number(fields[1].dropFirst(5)),
                  candidate > 0 else { return nil }
            beta = candidate
        } else {
            beta = nil
        }
    }

    private static func number(_ text: Substring) -> Int? {
        guard !text.isEmpty, (text.count == 1 || text.first != "0"),
              text.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return Int(text)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.core != rhs.core { return lhs.core.lexicographicallyPrecedes(rhs.core) }
        switch (lhs.beta, rhs.beta) {
        case (nil, _): return false
        case (_, nil): return true
        case (let left?, let right?): return left < right
        }
    }
}

struct ReleaseChecker {
    typealias Fetch = (URLRequest, @escaping (Data?, URLResponse?, Error?) -> Void) -> Void
    static let endpoint = URL(string: "https://api.github.com/repos/nico-zhuang/mindnode-reconstruction/releases?per_page=30")!
    static let releasesPage = URL(string: "https://github.com/nico-zhuang/mindnode-reconstruction/releases")!
    private static let maxBytes = 128 * 1024
    private static let maxReleases = 30
    private let fetch: Fetch

    init(fetch: @escaping Fetch = ReleaseChecker.liveFetch) { self.fetch = fetch }

    func check(currentVersion: String, channel: ReleaseChannel,
               completion: @escaping (Result<ReleaseCheckOutcome, Error>) -> Void) {
        let normalized = currentVersion.hasPrefix("v") ? String(currentVersion.dropFirst()) : currentVersion
        guard let installed = ReleaseVersion(normalized) else {
            completion(.failure(ReleaseCheckError.invalidVersion))
            return
        }
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("OpenMindFlow-Release-Checker/1.0", forHTTPHeaderField: "User-Agent")
        let lock = NSLock()
        var finished = false
        fetch(request) { data, response, error in
            lock.lock()
            let first = !finished
            finished = true
            lock.unlock()
            guard first else { return }
            if let error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse,
                  http.url?.absoluteString == Self.endpoint.absoluteString else {
                completion(.failure(ReleaseCheckError.invalidResponse))
                return
            }
            if http.statusCode == 403 || http.statusCode == 404 {
                completion(.failure(ReleaseCheckError.accessRestricted))
                return
            }
            guard http.statusCode == 200, let data else {
                completion(.failure(ReleaseCheckError.invalidResponse))
                return
            }
            guard data.count <= Self.maxBytes else { completion(.failure(ReleaseCheckError.tooLarge)); return }
            do { completion(.success(try Self.release(in: data, newerThan: installed, channel: channel))) }
            catch { completion(.failure(error)) }
        }
    }

    private static func release(in data: Data, newerThan installed: ReleaseVersion,
                                channel: ReleaseChannel) throws -> ReleaseCheckOutcome {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              json.count <= maxReleases else { throw ReleaseCheckError.untrustedMetadata }
        var best: (ReleaseVersion, ReleaseInfo)?
        for element in json {
            guard let object = element as? [String: Any],
                  let rawTag = object["tag_name"] as? String,
                  let rawPage = object["html_url"] as? String,
                  let draft = object["draft"] as? NSNumber, CFGetTypeID(draft) == CFBooleanGetTypeID(),
                  let prerelease = object["prerelease"] as? NSNumber,
                  CFGetTypeID(prerelease) == CFBooleanGetTypeID() else {
                throw ReleaseCheckError.untrustedMetadata
            }
            guard !draft.boolValue else { continue }
            guard rawTag.hasPrefix("v") else { continue }
            let version = String(rawTag.dropFirst())
            guard let parsed = ReleaseVersion(version),
                  (parsed.beta != nil) == prerelease.boolValue,
                  channel == .beta || parsed.beta == nil else { continue }
            let expectedPage = "\(releasesPage.absoluteString)/tag/\(rawTag)"
            guard rawPage == expectedPage, let page = URL(string: rawPage),
                  page.scheme == "https", page.host == "github.com", page.user == nil,
                  page.password == nil, page.port == nil, page.query == nil,
                  page.fragment == nil else { continue }
            if best == nil || best!.0 < parsed {
                best = (parsed, ReleaseInfo(version: version, pageURL: page))
            }
        }
        if let best, best.0 > installed { return .newer(best.1) }
        guard json.count < maxReleases else { throw ReleaseCheckError.incompleteListing }
        return best == nil ? .noPublishedRelease : .upToDate
    }

    private static func liveFetch(_ request: URLRequest,
                                  completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 10
        config.httpShouldSetCookies = false
        sessionFetch(configuration: config)(request, completion)
    }

    // Also lets tests route a real session/delegate through an ephemeral URLProtocol fixture.
    static func sessionFetch(configuration: URLSessionConfiguration,
                             onRedirect: (() -> Void)? = nil) -> Fetch {
        { request, completion in
            let delegate = BoundedReleaseFetch(completion: completion, onRedirect: onRedirect)
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            session.dataTask(with: request).resume()
        }
    }
}

private final class BoundedReleaseFetch: NSObject, URLSessionDataDelegate {
    private let completion: (Data?, URLResponse?, Error?) -> Void
    private let onRedirect: (() -> Void)?
    private var data = Data()
    private var response: URLResponse?
    private var finished = false

    init(completion: @escaping (Data?, URLResponse?, Error?) -> Void,
         onRedirect: (() -> Void)? = nil) {
        self.completion = completion
        self.onRedirect = onRedirect
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        onRedirect?()
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.response = response
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard !finished else { return }
        if chunk.count > 128 * 1024 - data.count {
            finished = true
            completion(nil, response, ReleaseCheckError.tooLarge)
            dataTask.cancel()
            session.invalidateAndCancel()
        } else {
            data.append(chunk)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard !finished else { return }
        finished = true
        completion(data, response, error)
        session.finishTasksAndInvalidate()
    }
}
