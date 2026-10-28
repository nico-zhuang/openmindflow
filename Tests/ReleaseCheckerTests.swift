import Foundation

// An ephemeral URLSession routes the actual data-task delegate through this local protocol.
private final class ReleaseFixtureProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var redirectedRequests = 0
    private static var cancellations = 0
    private static var scenario = "redirect"
    private var heldOversized = false

    static func configure(_ next: String) {
        lock.lock()
        scenario = next
        redirectedRequests = 0
        cancellations = 0
        lock.unlock()
    }

    static var counts: (redirected: Int, canceled: Int) {
        lock.lock(); defer { lock.unlock() }
        return (redirectedRequests, cancellations)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let client, let url = request.url else { return }
        Self.lock.lock()
        let selected = Self.scenario
        if url.path.hasSuffix("/redirected") { Self.redirectedRequests += 1 }
        Self.lock.unlock()
        if selected == "redirect" && !url.path.hasSuffix("/redirected") {
            let destination = URL(string: "https://api.github.com/redirected")!
            let redirect = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1",
                                           headerFields: ["Location": destination.absoluteString])!
            client.urlProtocol(self, wasRedirectedTo: URLRequest(url: destination), redirectResponse: redirect)
            client.urlProtocolDidFinishLoading(self)
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if selected == "oversized" {
            Self.lock.lock(); heldOversized = true; Self.lock.unlock()
            client.urlProtocol(self, didLoad: Data(repeating: 65, count: 128 * 1024))
            client.urlProtocol(self, didLoad: Data([66]))
            // Hold the task open: only its streaming size guard may finish it.
        } else {
            client.urlProtocol(self, didLoad: ReleaseCheckerTests.payload([ReleaseCheckerTests.item("v1.10.0")]))
            client.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        Self.lock.lock()
        if heldOversized { Self.cancellations += 1 }
        Self.lock.unlock()
    }
}

@main
enum ReleaseCheckerTests {
    static let endpoint = URL(string: "https://api.github.com/repos/nico-zhuang/mindnode-reconstruction/releases?per_page=30")!
    static let releasesPage = "https://github.com/nico-zhuang/mindnode-reconstruction/releases"

    static func item(_ tag: String, draft: Any = false, prerelease: Any? = nil,
                     page: String? = nil) -> [String: Any] {
        ["tag_name": tag, "html_url": page ?? "\(releasesPage)/tag/\(tag)",
         "draft": draft, "prerelease": prerelease ?? tag.contains("-beta.")]
    }

    static func payload(_ releases: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: releases)
    }

    static func check(current: String = "1.9.9", channel: ReleaseChannel = .stable,
                      data: Data = payload([item("v1.10.0")]), status: Int = 200,
                      responseURL: URL? = endpoint, failure: Error? = nil,
                      twice: Bool = false, nonHTTP: Bool = false)
        -> (Result<ReleaseCheckOutcome, Error>, Int, URLRequest?) {
        var calls = 0, request: URLRequest?, result: Result<ReleaseCheckOutcome, Error>?
        let checker = ReleaseChecker(fetch: { input, completion in
            request = input
            let response: URLResponse? = responseURL.map { url in
                nonHTTP ? URLResponse(url: url, mimeType: "application/json", expectedContentLength: -1,
                                      textEncodingName: nil) :
                    HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            }
            completion(data, response, failure)
            if twice { completion(data, response, failure) }
        })
        checker.check(currentVersion: current, channel: channel) { outcome in calls += 1; result = outcome }
        return (result!, calls, request)
    }

    static func expectNewer(_ result: Result<ReleaseCheckOutcome, Error>, _ version: String,
                            _ tag: String? = nil) {
        guard case .success(.newer(let info)) = result else { fatalError("Expected newer \(version): \(result)") }
        assert(info.version == version, "Expected \(version), received \(info.version)")
        assert(info.pageURL.absoluteString == "\(releasesPage)/tag/\(tag ?? "v\(version)")")
    }

    static func expectUpToDate(_ result: Result<ReleaseCheckOutcome, Error>) {
        guard case .success(.upToDate) = result else { fatalError("Expected up-to-date: \(result)") }
    }

    static func expectNoRelease(_ result: Result<ReleaseCheckOutcome, Error>) {
        guard case .success(.noPublishedRelease) = result else { fatalError("Expected no release: \(result)") }
    }

    static func rejected(_ result: Result<ReleaseCheckOutcome, Error>) {
        guard case .failure = result else { fatalError("Untrusted release metadata accepted: \(result)") }
    }

    static func expectIncompleteListing(_ result: Result<ReleaseCheckOutcome, Error>) {
        guard case .failure(let error) = result,
              case ReleaseCheckError.incompleteListing = error else {
            fatalError("Expected incomplete release listing: \(result)")
        }
        assert(error.localizedDescription.contains("Releases"), "Failure must identify the Releases page")
    }

    static func actualDelegate(_ scenario: String) -> (Result<ReleaseCheckOutcome, Error>, Int, Int) {
        ReleaseFixtureProtocol.configure(scenario)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReleaseFixtureProtocol.self]
        let lock = NSLock()
        var redirectsObserved = 0
        let checker = ReleaseChecker(fetch: ReleaseChecker.sessionFetch(configuration: config, onRedirect: {
            lock.lock(); redirectsObserved += 1; lock.unlock()
        }))
        let finished = DispatchSemaphore(value: 0)
        var result: Result<ReleaseCheckOutcome, Error>?
        var calls = 0
        checker.check(currentVersion: "1.9.9", channel: .stable) { value in
            lock.lock()
            calls += 1
            result = value
            lock.unlock()
            finished.signal()
        }
        guard finished.wait(timeout: .now() + 3) == .success else {
            fatalError("Real URLSession delegate did not complete for \(scenario)")
        }
        assert(finished.wait(timeout: .now() + 0.2) == .timedOut,
               "Real delegate completed twice for \(scenario)")
        lock.lock(); defer { lock.unlock() }
        return (result!, calls, redirectsObserved)
    }

    static func testActualSessionDelegate() {
        let (valid, validCalls, validRedirects) = actualDelegate("success")
        expectNewer(valid, "1.10.0")
        assert(validCalls == 1 && validRedirects == 0)

        let (redirect, redirectCalls, redirectDecisions) = actualDelegate("redirect")
        rejected(redirect)
        assert(redirectCalls == 1, "Redirect must complete only once")
        assert(redirectDecisions == 1, "The real URLSession redirect delegate must reject the hop")
        assert(ReleaseFixtureProtocol.counts.redirected == 0, "Delegate must not follow redirect")

        let (oversized, sizeCalls, sizeRedirects) = actualDelegate("oversized")
        assert(sizeRedirects == 0)
        guard case .failure(let error) = oversized, case ReleaseCheckError.tooLarge = error else {
            fatalError("Streaming body exceeding 128 KiB must be canceled: \(oversized)")
        }
        assert(sizeCalls == 1, "Cancel-induced completion must not fire twice")
        let deadline = Date().addingTimeInterval(2)
        while ReleaseFixtureProtocol.counts.canceled == 0 && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        assert(ReleaseFixtureProtocol.counts.canceled > 0, "Oversized task must cancel transport")
    }

    static func main() {
        testActualSessionDelegate()
        let (newer, calls, request) = check(twice: true)
        expectNewer(newer, "1.10.0")
        assert(calls == 1, "Transport callback must not invoke completion twice")
        assert(request?.httpMethod == "GET" && request?.url == endpoint)
        assert((request?.timeoutInterval ?? .infinity) == 10)
        assert(request?.httpShouldHandleCookies == false)
        assert(request?.value(forHTTPHeaderField: "User-Agent")?.contains("OpenMindFlow") == true)
        assert(request?.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        assert(ReleaseChecker.releasesPage.absoluteString == releasesPage)
        assert(ReleaseChannel.stable.rawValue == "stable" && ReleaseChannel.beta.rawValue == "beta")
        expectNoRelease(check(data: payload([item("1.10.0")])).0)
        expectNoRelease(check(channel: .beta, data: payload([item("1.10.0-beta.1")])).0)
        expectNewer(check(current: "v1.9.9", data: payload([item("v1.10.0")])).0, "1.10.0")

        let shuffled = payload([item("v1.9.0"), item("v1.11.0-beta.3"), item("v1.10.0"),
                                item("v1.2.99"), item("v1.11.0"), item("v1.11.0-beta.10")])
        expectNewer(check(data: shuffled).0, "1.11.0")
        expectNewer(check(channel: .beta, data: shuffled).0, "1.11.0")
        expectNewer(check(current: "1.11.0-beta.2", channel: .beta,
                          data: payload([item("v1.11.0-beta.1"), item("v1.11.0-beta.3")])).0,
                    "1.11.0-beta.3")
        expectNewer(check(channel: .beta, data: payload([item("v1.11.0-beta.2")])).0,
                    "1.11.0-beta.2")
        expectNewer(check(channel: .beta, data: payload([item("v1.11.0-beta.2"),
                                                        item("v1.11.0-beta.10")])).0,
                    "1.11.0-beta.10")
        expectNoRelease(check(data: payload([item("v1.11.0-beta.2")])).0)
        expectNewer(check(current: "1.11.0-beta.2", data: payload([item("v1.11.0")])).0,
                    "1.11.0")
        expectUpToDate(check(current: "1.11.0-beta.2", channel: .beta,
                             data: payload([item("v1.11.0-beta.1")])).0)
        expectUpToDate(check(current: "1.11.0", channel: .beta,
                             data: payload([item("v1.11.0-beta.100")])).0)
        expectUpToDate(check(current: "1.11.0", data: payload([item("v1.11.0")])).0)
        expectUpToDate(check(current: "2.0.0", data: payload([item("v1.11.0")])).0)
        expectNoRelease(check(data: payload([])).0)

        // A full first page cannot prove there is no older eligible release beyond it.
        let thirtyBetas = (1...30).map { item("v1.10.0-beta.\($0)") }
        expectIncompleteListing(check(data: payload(thirtyBetas)).0)
        let staleStableBehindBetas = Array(thirtyBetas.prefix(29)) + [item("v1.8.0")]
        expectIncompleteListing(check(data: payload(staleStableBehindBetas)).0)
        expectNoRelease(check(data: payload(Array(thirtyBetas.prefix(29)))).0)
        expectUpToDate(check(data: payload(Array(thirtyBetas.prefix(28)) + [item("v1.8.0")])).0)
        expectNewer(check(data: payload(Array(thirtyBetas.prefix(29)) + [item("v1.10.0")])).0,
                    "1.10.0")
        expectNewer(check(channel: .beta, data: payload(thirtyBetas)).0, "1.10.0-beta.30")

        let decoys = payload([item("v100.0.0", draft: true),
                              item("v99.0.0", prerelease: true),
                              item("v98.0.0-beta.1", prerelease: false),
                              item("v97.0.0", page: "https://github.com.evil.example/other"),
                              item("v1.10.0")])
        expectNewer(check(data: decoys).0, "1.10.0")
        expectNewer(check(channel: .beta, data: decoys).0, "1.10.0")
        expectNoRelease(check(data: payload([item("v1.10.0", draft: true)])).0)

        for bad in ["0.1", "v1.2", "1.02.3", "1.2.3-beta", "1.2.3-beta.0", "", "１.2.3",
                    "99999999999999999999999.0.0", "1.2.3+meta", "v1.2.3.4"] {
            let (result, _, request) = check(current: bad)
            rejected(result)
            assert(request == nil, "Malformed installed version must not initiate network: \(bad)")
        }
        for badTag in ["v1.2", "v01.2.3", "v1.2.3-beta", "v1.2.3-beta.0", "v1.2.3-beta.01",
                       "1.2.3+meta", "v1.2.3/../other", "v99999999999999999999999.0.0"] {
            expectNoRelease(check(data: payload([item(badTag)])).0)
        }
        for badPage in ["http://github.com/nico-zhuang/mindnode-reconstruction/releases/tag/v1.10.0",
                        "https://github.com.evil.example/nico-zhuang/mindnode-reconstruction/releases/tag/v1.10.0",
                        "https://github.com@evil.example/nico-zhuang/mindnode-reconstruction/releases/tag/v1.10.0",
                        "https://github.com:444/nico-zhuang/mindnode-reconstruction/releases/tag/v1.10.0",
                        "https://github.com/nico-zhuang/other/releases/tag/v1.10.0",
                        "https://github.com/nico-zhuang/mindnode-reconstruction/releases/tag/v1.10.0?download=1",
                        "https://github.com/nico-zhuang/mindnode-reconstruction/releases/tag/v1.10.0#asset",
                        "https://github.com/nico-zhuang/mindnode-reconstruction/releases/tag/%761.10.0",
                        "/nico-zhuang/mindnode-reconstruction/releases/tag/v1.10.0"] {
            expectNoRelease(check(data: payload([item("v1.10.0", page: badPage)])).0)
        }
        for invalid in [payload([item("v1.10.0", draft: "false")]),
                        payload([item("v1.10.0", prerelease: "false")]),
                        Data("not json".utf8), Data("{}".utf8)] {
            rejected(check(data: invalid).0)
        }
        rejected(check(data: Data(repeating: 65, count: 131_073)).0)
        rejected(check(data: payload(Array(repeating: item("v1.10.0"), count: 31))).0)
        for status in [403, 404] {
            guard case .failure(let error) = check(status: status).0,
                  case ReleaseCheckError.accessRestricted = error else {
                fatalError("HTTP \(status) must report restricted access")
            }
        }
        for status in [301, 302, 307, 500] { rejected(check(status: status).0) }
        rejected(check(responseURL: URL(string: "https://example.org/redirect")!).0)
        rejected(check(responseURL: URL(string: "https://api.github.com/repos/nico-zhuang/mindnode-reconstruction/releases/latest")!).0)
        rejected(check(responseURL: nil).0)
        rejected(check(nonHTTP: true).0)
        rejected(check(failure: URLError(.timedOut)).0)
        print("release list channels, semver, restrictions, trust boundaries and one-shot tests passed")
    }
}
