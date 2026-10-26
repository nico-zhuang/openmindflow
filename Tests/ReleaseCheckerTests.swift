import Foundation

@main
enum ReleaseCheckerTests {
    static let endpoint = URL(string: "https://api.github.com/repos/nico-zhuang/mindnode-reconstruction/releases/latest")!
    static let page = "https://github.com/nico-zhuang/mindnode-reconstruction/releases/tag/v1.10.0"

    static func payload(tag: String = "v1.10.0", pageURL: String = page,
                        draft: Any = false, prerelease: Any = false) -> Data {
        try! JSONSerialization.data(withJSONObject: ["tag_name": tag, "html_url": pageURL,
                                               "draft": draft, "prerelease": prerelease])
    }

    static func check(current: String = "1.9.9", data: Data? = nil, status: Int = 200,
                      responseURL: URL? = endpoint, failure: Error? = nil,
                      twice: Bool = false, nonHTTP: Bool = false) -> (Result<ReleaseInfo?, Error>, Int, URLRequest?) {
        var calls = 0, request: URLRequest?, result: Result<ReleaseInfo?, Error>?
        let checker = ReleaseChecker(fetch: { input, completion in
            request = input
            let response: URLResponse? = responseURL.map { url in
                nonHTTP ? URLResponse(url: url, mimeType: "application/json", expectedContentLength: -1,
                                      textEncodingName: nil) :
                    HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            }
            completion(data ?? payload(), response, failure)
            if twice { completion(data ?? payload(), response, failure) }
        })
        checker.check(currentVersion: current) { outcome in calls += 1; result = outcome }
        return (result!, calls, request)
    }

    static func rejected(_ value: Result<ReleaseInfo?, Error>) {
        guard case .failure = value else { fatalError("Untrusted update metadata accepted") }
    }

    static func main() {
        let (newer, calls, request) = check(twice: true)
        guard case .success(let info?) = newer else { fatalError("New stable release omitted") }
        assert(info.version == "1.10.0" && info.pageURL.absoluteString == page)
        assert(calls == 1, "Transport callback may not invoke user completion twice")
        assert(request?.httpMethod == "GET" && request?.url == endpoint)
        assert((request?.timeoutInterval ?? .infinity) <= 10)
        assert(request?.value(forHTTPHeaderField: "User-Agent")?.contains("OpenMindFlow") == true)
        assert(request?.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        let bare = "https://github.com/nico-zhuang/mindnode-reconstruction/releases/tag/1.10.0"
        guard case .success(let unprefixed?) = check(data: payload(tag: "1.10.0", pageURL: bare)).0 else {
            fatalError("Strict numeric tag without v should be accepted")
        }
        assert(unprefixed.version == "1.10.0" && unprefixed.pageURL.absoluteString == bare)

        for (current, tag) in [("1.10.0", "v1.10.0"), ("2.0.0", "v1.10.0"),
                               ("2.0.0", "v1.9.9")] {
            let matchingPage = "https://github.com/nico-zhuang/mindnode-reconstruction/releases/tag/\(tag)"
            guard case .success(nil) = check(current: current, data: payload(tag: tag, pageURL: matchingPage)).0 else {
                fatalError("Older or equal version incorrectly notified")
            }
        }
        for bad in ["0.1", "v1.2", "1.02.3", "1.2.3-beta", "", "99999999999999999999999.0.0"] {
            let (result, _, request) = check(current: bad)
            rejected(result)
            assert(request == nil, "Malformed current version must not initiate network")
        }
        for badTag in ["v1.2", "v01.2.3", "v1.2.3-beta", "1.2.3+meta", "v1.2.3/../other",
                       "v99999999999999999999999.0.0"] {
            rejected(check(data: payload(tag: badTag)).0)
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
            rejected(check(data: payload(pageURL: badPage)).0)
        }
        rejected(check(data: payload(tag: "1.10.0", pageURL: page)).0)
        rejected(check(data: payload(draft: true)).0)
        rejected(check(data: payload(prerelease: true)).0)
        rejected(check(data: payload(draft: "false")).0)
        rejected(check(data: payload(prerelease: "false")).0)
        rejected(check(data: Data("not json".utf8)).0)
        rejected(check(data: Data(repeating: 65, count: 131_073)).0)
        rejected(check(status: 302).0)
        rejected(check(status: 500).0)
        rejected(check(responseURL: URL(string: "https://example.org/redirect")!).0)
        rejected(check(responseURL: nil).0)
        rejected(check(nonHTTP: true).0)
        rejected(check(failure: URLError(.timedOut)).0)
        print("injected GitHub release metadata, URL trust, semver and one-shot completion tests passed")
    }
}
