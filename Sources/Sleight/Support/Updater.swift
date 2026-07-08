import AppKit
import Foundation

/// Self-updater backed by GitHub Releases. Checks periodically, downloads a
/// newer Sleight.app quietly into a staging folder, and applies it either
/// when the Mac wakes from sleep (so the swap+relaunch is invisible) or when
/// the user clicks the menu item. Because builds are signed with the stable
/// local identity, updates do NOT reset permission grants.
@MainActor
@Observable
final class Updater {
    static let shared = Updater()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case downloading(String)
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
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    private init() {}

    func start() {
        // First check shortly after launch, then twice a day.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            await self?.check()
        }
        let timer = Timer(timeInterval: 6 * 3600, repeats: true) { _ in
            Task { @MainActor in await Updater.shared.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if case .staged = Updater.shared.state,
                   ConfigStore.shared.config.autoUpdate {
                    Updater.shared.applyStagedUpdate()
                }
            }
        }
    }

    func check() async {
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
            SleightLog.log("updater: downloading \(latest)")
            state = .downloading(latest)
            try await download(zipURL, version: latest)
            state = .staged(latest)
            SleightLog.log("updater: \(latest) staged, applies on wake or via menu")
        } catch {
            SleightLog.log("updater: check failed: \(error.localizedDescription)")
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
    func applyStagedUpdate() {
        guard case .staged = state else { return }
        let destination = Bundle.main.bundleURL
        SleightLog.log("updater: applying staged update to \(destination.path)")
        let script = """
        sleep 1
        rm -rf "\(destination.path)"
        ditto "\(stagedAppURL.path)" "\(destination.path)"
        rm -rf "\(stagingDir.path)"
        open "\(destination.path)"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", script]
        try? process.run()
        NSApp.terminate(nil)
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
