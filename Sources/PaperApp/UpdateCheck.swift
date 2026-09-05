import Foundation

/// The manual update check, and the one network call the application makes.
///
/// The rule, carried over from PaperV2 and worth restating so it is not
/// widened later: nothing here runs unless the user picks the menu item.
/// There is no check on launch and none on a timer, because a check that
/// runs by itself turns the release server's logs into an audience counter,
/// which is telemetry whoever is holding it. The check reports and offers
/// the releases page. It never downloads, installs, or restarts anything.

/// A release version read as numbers, so 0.10.0 is newer than 0.9.0.
/// Comparing the strings would say otherwise, and would only start being
/// wrong at the tenth release.
struct UpdateVersion: Comparable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int

    /// Reads `1.2.3`, tolerating a `v` prefix and filling missing parts
    /// with zero. Everything from the first dash or plus describes a
    /// pre-release or build, which the comparison ignores. A tag that does
    /// not start with a number reads as nothing: guessing at it would mean
    /// either a phantom update or a missed one.
    init?(_ text: String) {
        var parts = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".", omittingEmptySubsequences: false)
            .makeIterator()

        func number(_ part: Substring?, required: Bool) -> Int? {
            guard var part else { return required ? nil : 0 }
            if required, part.hasPrefix("v") || part.hasPrefix("V") {
                part = part.dropFirst()
            }
            if !required, let end = part.firstIndex(where: { $0 == "-" || $0 == "+" }) {
                part = part[..<end]
            }
            return Int(part)
        }

        guard let major = number(parts.next(), required: true) else { return nil }
        let minor = number(parts.next(), required: false)
        let patch = number(parts.next(), required: false)
        guard let minor, let patch else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: UpdateVersion, rhs: UpdateVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

enum UpdateCheck {
    static let latestReleaseAPI = "https://api.github.com/repos/UsePaper/PaperV3/releases/latest"
    /// A constant on purpose: the check never opens a URL it was handed,
    /// because the only page it ever needs to reach is our own.
    static let releasesPage = "https://github.com/UsePaper/PaperV3/releases/latest"

    /// Long enough for a slow connection, short enough that a black hole
    /// does not leave the user staring at a menu that did nothing.
    static let timeout: TimeInterval = 10

    /// What the alert has to say.
    enum Outcome: Equatable {
        case available(latest: String, current: String)
        case current(String)
        /// Offline, rate limited, or nothing published yet. None of that is
        /// worth a stack trace, and none of it means an update does or does
        /// not exist.
        case unknown
    }

    /// The version this build carries, from the bundle. A bare binary run
    /// outside a bundle has none, and the check reports that it could not
    /// compare rather than inventing one.
    static var currentVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// The comparison alone, pure so a test can drive it without a network.
    static func outcome(currentTag: String?, latestTag: String?) -> Outcome {
        guard let latestTag else { return .unknown }
        let display = latestTag.hasPrefix("v") ? String(latestTag.dropFirst()) : latestTag
        guard let currentTag,
              let current = UpdateVersion(currentTag),
              let latest = UpdateVersion(latestTag)
        else { return .unknown }
        if current < latest {
            return .available(latest: display, current: currentTag)
        }
        return .current(currentTag)
    }

    /// Asks GitHub for the latest release tag and calls back on the main
    /// queue. One request, ephemeral, no cache and no cookies: the session
    /// leaves nothing behind that a later launch could send back.
    static func run(completion: @escaping (Outcome) -> Void) {
        var request = URLRequest(url: URL(string: latestReleaseAPI)!)
        request.timeoutInterval = timeout
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Paper/\(currentVersion ?? "0")", forHTTPHeaderField: "User-Agent")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration)

        let task = session.dataTask(with: request) { data, response, _ in
            let tag = latestTag(data: data, response: response)
            let result = outcome(currentTag: currentVersion, latestTag: tag)
            DispatchQueue.main.async { completion(result) }
        }
        task.resume()
        session.finishTasksAndInvalidate()
    }

    /// The tag out of the response, or nil for anything short of a readable
    /// release. Before the first published release the API answers 404,
    /// which is not a release either.
    private static func latestTag(data: Data?, response: URLResponse?) -> String? {
        guard let data,
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["tag_name"] as? String
    }
}
