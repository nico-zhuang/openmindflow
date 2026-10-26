import Foundation
import CoreFoundation

struct ReleaseInfo {
    let version: String
    let pageURL: URL
}

enum ReleaseCheckError: LocalizedError {
    case invalidVersion, invalidResponse, untrustedMetadata, tooLarge

    var errorDescription: String? {
        switch self {
        case .invalidVersion: "The installed or release version is not a numeric X.Y.Z version."
        case .invalidResponse: "GitHub did not return a valid release response."
        case .untrustedMetadata: "The release page or metadata could not be verified."
        case .tooLarge: "The release response exceeds the 128 KiB metadata limit."
        }
    }
}

struct ReleaseChecker {
    typealias Fetch = (URLRequest, @escaping (Data?, URLResponse?, Error?) -> Void) -> Void
    static let endpoint = URL(string: "https://api.github.com/repos/nico-zhuang/mindnode-reconstruction/releases/latest")!
    private let fetch: Fetch

    init(fetch: @escaping Fetch = ReleaseChecker.liveFetch) { self.fetch = fetch }

    func check(currentVersion: String, completion: @escaping (Result<ReleaseInfo?, Error>) -> Void) {
        guard let installed = Self.components(currentVersion) else {
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
                  http.url?.absoluteString == Self.endpoint.absoluteString,
                  (200...299).contains(http.statusCode), let data else {
                completion(.failure(ReleaseCheckError.invalidResponse))
                return
            }
            guard data.count <= 128 * 1024 else { completion(.failure(ReleaseCheckError.tooLarge)); return }
            do { completion(.success(try Self.release(in: data, newerThan: installed))) }
            catch { completion(.failure(error)) }
        }
    }

    private static func components(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { part -> Int? in
            guard !part.isEmpty, (part.count == 1 || part.first != "0"),
                  part.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
            return Int(part)
        }
        return numbers.count == 3 ? numbers : nil
    }

    private static func release(in data: Data, newerThan installed: [Int]) throws -> ReleaseInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawTag = json["tag_name"] as? String,
              let rawPage = json["html_url"] as? String,
              let draft = json["draft"] as? NSNumber, CFGetTypeID(draft) == CFBooleanGetTypeID(),
              let prerelease = json["prerelease"] as? NSNumber, CFGetTypeID(prerelease) == CFBooleanGetTypeID(),
              !draft.boolValue, !prerelease.boolValue else { throw ReleaseCheckError.untrustedMetadata }
        let version = rawTag.hasPrefix("v") ? String(rawTag.dropFirst()) : rawTag
        guard let numbers = components(version) else { throw ReleaseCheckError.invalidVersion }
        let expectedPage = "https://github.com/nico-zhuang/mindnode-reconstruction/releases/tag/\(rawTag)"
        guard rawPage == expectedPage, let page = URL(string: rawPage),
              page.scheme == "https", page.host == "github.com", page.user == nil,
              page.password == nil, page.port == nil, page.query == nil,
              page.fragment == nil else { throw ReleaseCheckError.untrustedMetadata }
        guard installed.lexicographicallyPrecedes(numbers) else { return nil }
        return ReleaseInfo(version: version, pageURL: page)
    }

    private static func liveFetch(_ request: URLRequest,
                                  completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 10
        let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        session.dataTask(with: request) { data, response, error in
            completion(data, response, error)
            session.finishTasksAndInvalidate()
        }.resume()
    }
}

private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
