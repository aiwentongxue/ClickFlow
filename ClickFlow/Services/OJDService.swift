import AppKit
import CryptoKit
import Foundation

struct OJDError: LocalizedError, Sendable {
    var detail: String
    var errorDescription: String? { detail }
    static func message(_ key: String.LocalizationValue) -> OJDError { OJDError(detail: String(localized: key)) }
}

/// Shell-free process arguments and bounded execution for dependency inspection.
enum OJDCommand {
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 20) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        // Files avoid deadlocking when a child fills stderr/stdout before exiting.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let out = root.appendingPathComponent("stdout"), err = root.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: out.path, contents: nil)
        FileManager.default.createFile(atPath: err.path, contents: nil)
        let output = try FileHandle(forWritingTo: out), errors = try FileHandle(forWritingTo: err)
        defer { try? output.close(); try? errors.close() }
        process.standardOutput = output; process.standardError = errors
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            let grace = Date().addingTimeInterval(1)
            while process.isRunning, Date() < grace { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw OJDError.message("ojd.error.timeout")
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = (try? Data(contentsOf: err)) ?? Data()
            throw OJDError(detail: String(decoding: data.suffix(4096), as: UTF8.self))
        }
        return try Data(contentsOf: out)
    }
}

struct OJDPermissionStatus: Decodable, Sendable {
    var inputRead: String
    var inputInject: String
    static let unknown = OJDPermissionStatus(inputRead: "Unknown", inputInject: "Unknown")

    static func decodeStatus(_ data: Data) throws -> OJDPermissionStatus {
        struct Status: Decodable { var permissions: OJDPermissionStatus }
        return try JSONDecoder().decode(Status.self, from: data).permissions
    }
}

struct OJDService: Sendable {
    static let version = "0.6.0-alpha.1"
    static let sha256 = "d2b771ffe4382b7bfd218932c7003227216d334a14154e95976c4f114b1c2056"
    static let appURL = URL(fileURLWithPath: "/Applications/OpenJoystickDriver.app")
    static let downloadURL = URL(string: "https://github.com/xsyetopz/OpenJoystickDriver/releases/download/0.6.0-alpha.1/OpenJoystickDriver-0.6.0-alpha.1-macOS.dmg")!
    static var supportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClickFlow/OJD", isDirectory: true)
    }

    func verify(app: URL = Self.appURL) throws {
        guard FileManager.default.fileExists(atPath: app.path) else { throw OJDError.message("ojd.error.missing") }
        let info = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: info, format: nil) as? [String: Any]
        guard plist?["CFBundleIdentifier"] as? String == "com.openjoystickdriver",
              plist?["CFBundleShortVersionString"] as? String == Self.version else { throw OJDError.message("ojd.error.version") }
        _ = try OJDCommand.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R",
            "=anchor apple generic and identifier \"com.openjoystickdriver\" and certificate leaf[subject.OU] = \"9PQP6CDMQT\"", app.path])
        let data = try OJDCommand.run("/usr/bin/codesign", ["-d", "--entitlements", ":-", "--xml", app.path])
        let entitlements = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        guard entitlements?["com.apple.developer.hid.virtual.device"] as? Bool == true else { throw OJDError.message("ojd.error.entitlement") }
        _ = try OJDCommand.run("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path], timeout: 45)
    }

    func cli() throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: Self.supportURL, withIntermediateDirectories: true)
        let target = Self.appURL.appendingPathComponent("Contents/MacOS/OpenJoystickDriver")
        let link = Self.supportURL.appendingPathComponent("ojd")
        if (try? fm.destinationOfSymbolicLink(atPath: link.path)) == target.path { return link }
        guard !fm.fileExists(atPath: link.path), (try? fm.destinationOfSymbolicLink(atPath: link.path)) == nil else {
            throw OJDError.message("ojd.error.cliConflict")
        }
        try fm.createSymbolicLink(at: link, withDestinationURL: target)
        return link
    }

    func start() throws -> URL {
        try verify()
        let cli = try cli()
        _ = try OJDCommand.run(cli.path, ["--json", "--no-input", "--no-color", "--timeout", "8", "service", "start"], timeout: 12)
        let data = try status(cli: cli)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let service = json["service"] as? [String: Any], service["state"] as? String == "Running",
              service["version"] as? String == Self.version else { throw OJDError.message("ojd.error.notRunning") }
        let permissions = try OJDPermissionStatus.decodeStatus(data)
        guard permissions.inputRead == "Granted", permissions.inputInject == "Granted" else {
            throw OJDError.message("ojd.error.permissions")
        }
        return cli
    }

    func status(cli: URL? = nil) throws -> Data {
        let executable: URL
        if let cli { executable = cli }
        else { try verify(); executable = try self.cli() }
        return try OJDCommand.run(executable.path, ["--json", "--no-input", "--no-color", "--timeout", "2", "status"], timeout: 5)
    }

    func install() async throws {
        if FileManager.default.fileExists(atPath: Self.appURL.path) { try verify(); _ = try cli(); return }
        let (download, response) = try await URLSession.shared.download(from: Self.downloadURL)
        defer { try? FileManager.default.removeItem(at: download) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw OJDError.message("ojd.error.download") }
        let data = try Data(contentsOf: download, options: .mappedIfSafe)
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == Self.sha256 else {
            throw OJDError.message("ojd.error.hash")
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("ClickFlow-OJD-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let dmg = temporary.appendingPathComponent("OJD.dmg"), mount = temporary.appendingPathComponent("volume")
        try FileManager.default.copyItem(at: download, to: dmg)
        _ = try OJDCommand.run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-mountpoint", mount.path, dmg.path], timeout: 30)
        defer { _ = try? OJDCommand.run("/usr/bin/hdiutil", ["detach", mount.path], timeout: 30) }
        let source = mount.appendingPathComponent("OpenJoystickDriver.app")
        try verify(app: source)
        // Preserve the vendor's signed bundle. Never overwrite another installation.
        if FileManager.default.isWritableFile(atPath: "/Applications") {
            let staging = URL(fileURLWithPath: "/Applications/.ClickFlow-OJD-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: staging) }
            _ = try OJDCommand.run("/usr/bin/ditto", [source.path, staging.path], timeout: 60)
            try FileManager.default.moveItem(at: staging, to: Self.appURL)
        } else {
            func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
            let staging = "/Applications/.ClickFlow-OJD-\(UUID().uuidString)"
            let stagedApp = staging + "/OpenJoystickDriver.app"
            // Move into the parent directory with the original basename. If an
            // installation appears concurrently, mv -n leaves it untouched.
            // Always remove our staging directory, including after copy failure.
            let cleanup = "/bin/rm -rf " + quote(staging)
            let command = "set -e; trap " + quote(cleanup) + " EXIT; /bin/mkdir " + quote(staging)
                + "; /usr/bin/ditto " + quote(source.path) + " " + quote(stagedApp)
                + "; /bin/mv -n " + quote(stagedApp) + " /Applications/"
                + "; test ! -e " + quote(stagedApp)
            let literal = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            _ = try OJDCommand.run("/usr/bin/osascript", ["-e", "do shell script \"\(literal)\" with administrator privileges"], timeout: 180)
        }
        try verify(); _ = try cli()
    }
}
