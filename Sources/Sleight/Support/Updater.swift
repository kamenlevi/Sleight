import AppKit
import Foundation

/// Update checker backed by GitHub Releases. Checks periodically and only
/// ever *tells* the user a newer version exists — nothing is downloaded or
/// installed until they click Install (menu bar or Settings → General).
/// Because builds are signed with the stable local identity, updates do NOT
/// reset permission grants.
@MainActor
@Observable
final class Updater {
    static let shared = Updater()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        /// A newer release exists; nothing has been downloaded yet.
        case available(String)
        case downloading(String)
        /// Downloaded and verified, ready to swap in on the user's click.
        case staged(String)
        case failed(String)
    }

    private(set) var state: State = .idle

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private let stagingDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Sleight/Update")
    private var stagedAppURL: URL { stagingDir.appendingPathComponent("Sleight.app") }
    /// Zip asset of the release currently in `.available`.
    private var availableZipURL: URL?
    private var timer: Timer?

    private init() {}

    // MARK: - Install location

    /// True when macOS App Translocation is running us from a randomized
    /// read-only mount — the fate of a quarantined app launched straight from
    /// the folder it was unzipped into. Updates written to that path can
    /// never succeed, and permission grants made against it don't stick.
    static var isTranslocated: Bool {
        Bundle.main.bundleURL.path.contains("/AppTranslocation/")
    }

    /// Where updates are written: the running bundle's location normally, or
    /// the canonical Applications folder when the bundle path is unusable
    /// (translocated read-only mount).
    private var installDestination: URL {
        guard Self.isTranslocated else { return Bundle.main.bundleURL }
        let applications = URL(fileURLWithPath: "/Applications")
        if FileManager.default.isWritableFile(atPath: applications.path) {
            return applications.appendingPathComponent("Sleight.app")
        }
        let userApps = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications")
        try? FileManager.default.createDirectory(at: userApps, withIntermediateDirectories: true)
        return userApps.appendingPathComponent("Sleight.app")
    }

    /// Called first thing at launch. If we're running translocated, install
    /// this bundle into Applications, strip quarantine, and relaunch from
    /// there — otherwise self-update is impossible (the "restart to update"
    /// that never installs). Returns true when a relaunch is under way and
    /// the caller should stop launching.
    @discardableResult
    static func repairInstallLocationIfNeeded() -> Bool {
        guard isTranslocated else { return false }
        let source = Bundle.main.bundleURL
        let destination = shared.installDestination
        SleightLog.log("launch: running translocated from \(source.path) — installing to \(destination.path) and relaunching")
        shared.runDetachedSwap(from: source, to: destination, clearStagingOnSuccess: false)
        NSApp.terminate(nil)
        return true
    }

    func start() {
        // An update downloaded in a previous run stays waiting for the user's
        // click — it is never applied behind their back.
        if let staged = stagedVersion(), Self.isVersion(staged, newerThan: Self.currentVersion) {
            SleightLog.log("updater: \(staged) is downloaded and waiting — install from the menu or Settings")
            state = .staged(staged)
        } else {
            try? FileManager.default.removeItem(at: stagingDir)
        }

        // First check shortly after launch, then twice a day. Checks only
        // look — they never download or install anything.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            await self?.check()
        }
        let timer = Timer(timeInterval: 6 * 3600, repeats: true) { _ in
            Task { @MainActor in await Updater.shared.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Looks for a newer release and reports it. Checking never downloads or
    /// installs anything — both "Check Now" and the background timer stop at
    /// `.available`; installing takes a separate explicit click.
    func check(userInitiated: Bool = false) async {
        if case .downloading = state { return }
        if case .staged = state { return }
        state = .checking
        do {
            var request = URLRequest(url: URL(string:
                "https://api.github.com/repos/kamenlevi/Sleight/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                state = .upToDate
                return
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            guard Self.isVersion(latest, newerThan: Self.currentVersion) else {
                SleightLog.log("updater: \(Self.currentVersion) is current (latest \(latest))")
                state = .upToDate
                return
            }
            guard let assets = json["assets"] as? [[String: Any]],
                  let zipURLString = assets
                    .compactMap({ $0["browser_download_url"] as? String })
                    .first(where: { $0.hasSuffix(".zip") }),
                  let zipURL = URL(string: zipURLString) else {
                state = .upToDate
                return
            }
            availableZipURL = zipURL
            SleightLog.log("updater: \(latest) is available — waiting for the user (userInitiated=\(userInitiated))")
            state = .available(latest)
        } catch {
            SleightLog.log("updater: check failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    /// The user clicked Install on an `.available` version: download, stage,
    /// swap, relaunch.
    func installAvailable() async {
        guard case .available(let version) = state, let zipURL = availableZipURL else { return }
        SleightLog.log("updater: downloading \(version)")
        state = .downloading(version)
        do {
            try await download(zipURL, version: version)
            state = .staged(version)
            applyStagedUpdate()
        } catch {
            SleightLog.log("updater: download of \(version) failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    private func download(_ url: URL, version: String) async throws {
        let (tempFile, _) = try await URLSession.shared.download(from: url)
        try? FileManager.default.removeItem(at: stagingDir)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-xk", tempFile.path, stagingDir.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0,
              FileManager.default.fileExists(atPath: stagedAppURL.appendingPathComponent("Contents/MacOS/Sleight").path) else {
            throw NSError(domain: "Sleight", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "downloaded archive did not contain Sleight.app",
            ])
        }
    }

    /// Swap the staged app into place and relaunch. Runs the swap in a
    /// detached shell so replacing our own bundle mid-execution is safe.
    /// Only ever reached from a user click.
    func applyStagedUpdate() {
        guard case .staged(let version) = state else { return }
        let destination = installDestination
        SleightLog.log("updater: applying staged \(version) to \(destination.path) (translocated=\(Self.isTranslocated))")
        runDetachedSwap(from: stagedAppURL, to: destination, clearStagingOnSuccess: true)
        NSApp.terminate(nil)
    }

    /// The detached swap script. Every step is appended to Sleight.log so a
    /// failed install on any machine can be diagnosed after the fact; the
    /// source is only cleaned up once the copy verifiably succeeded, and the
    /// old app is relaunched if the swap failed, so a failure is never silent.
    private func runDetachedSwap(from source: URL, to destination: URL, clearStagingOnSuccess: Bool) {
        let cleanup = clearStagingOnSuccess ? "rm -rf \(shq(stagingDir.path))" : "true"
        let dest = shq(destination.path)
        let src = shq(source.path)
        let old = shq(destination.path + ".previous")
        let script = """
        exec >> "$HOME/Library/Logs/Sleight.log" 2>&1
        sleep 1
        echo "$(date '+%Y-%m-%d %H:%M:%S.000') updater-swap: \(src) -> \(dest)"
        rm -rf \(old)
        if [ -e \(dest) ]; then mv \(dest) \(old) || rm -rf \(dest); fi
        if ditto \(src) \(dest) && [ -x \(dest)/Contents/MacOS/Sleight ]; then
            rm -rf \(old)
            xattr -dr com.apple.quarantine \(dest) 2>/dev/null
            \(cleanup)
            echo "$(date '+%Y-%m-%d %H:%M:%S.000') updater-swap: ok, relaunching"
            open \(dest)
        else
            rm -rf \(dest)
            if [ -e \(old) ]; then mv \(old) \(dest); fi
            echo "$(date '+%Y-%m-%d %H:%M:%S.000') updater-swap: FAILED (copy did not complete) — relaunching previous app"
            open \(dest) 2>/dev/null || open \(src)
        fi
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", script]
        do {
            try process.run()
        } catch {
            SleightLog.log("updater-swap: could not launch swap shell: \(error.localizedDescription)")
        }
    }

    /// Single-quote a path for safe embedding in the swap script.
    private func shq(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func stagedVersion() -> String? {
        let plist = stagedAppURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return dict["CFBundleShortVersionString"] as? String
    }

    /// Semver-ish comparison: "1.10.0" > "1.9.1".
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let av = a.split(separator: ".").map { Int($0) ?? 0 }
        let bv = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(av.count, bv.count) {
            let x = i < av.count ? av[i] : 0
            let y = i < bv.count ? bv[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
