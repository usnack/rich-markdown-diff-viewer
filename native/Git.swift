import Foundation
import Darwin

struct AppError: LocalizedError { let message: String; var errorDescription: String? { message } }
struct Change: Codable { var path: String; var oldPath: String; var status: String; var staged: Bool = false; var unstaged: Bool = false; var id: String { path } }
struct Snapshot: Codable { var before: String; var after: String; var beforeLabel: String; var afterLabel: String; var assets: [String: [String: String]]; var error: String? }
final class Git {
    let root: URL
    init(_ folder: URL) throws {
        let path = try Self.run(folder, ["rev-parse", "--show-toplevel"])
        guard let str = String(data: path, encoding: .utf8) else { throw AppError(message: "저장소 경로가 UTF-8이 아닙니다.") }
        root = URL(fileURLWithPath: String(str.dropLast())).standardizedFileURL.resolvingSymlinksInPath()
    }
    static func run(_ folder: URL, _ args: [String]) throws -> Data {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["--no-optional-locks", "-c", "core.quotepath=false", "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null"] + args; p.currentDirectoryURL = folder
        var env = ProcessInfo.processInfo.environment; env["GIT_TERMINAL_PROMPT"] = "0"; env["GIT_CONFIG_NOSYSTEM"] = "1"; env["GIT_LITERAL_PATHSPECS"] = "1"; p.environment = env
        let pipe = Pipe(); p.standardOutput = pipe; p.standardInput = FileHandle.nullDevice
        let errURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        let err = try FileHandle(forWritingTo: errURL); p.standardError = err
        defer { try? err.close(); try? FileManager.default.removeItem(at: errURL) }
        try p.run()
        let timeout = DispatchWorkItem { if p.isRunning { p.terminate(); DispatchQueue.global().asyncAfter(deadline: .now() + 1) { if p.isRunning { kill(p.processIdentifier, SIGKILL) } } } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: timeout)
        var result = Data(); var oversized = false
        while true {
            let chunk = pipe.fileHandleForReading.readData(ofLength: 65536)
            if chunk.isEmpty { break }; result.append(chunk)
            if result.count > 64 * 1024 * 1024 { oversized = true; p.terminate(); try? pipe.fileHandleForReading.close(); break }
        }
        p.waitUntilExit(); timeout.cancel()
        if oversized { throw AppError(message: "Git 응답이 64MB를 초과했습니다.") }
        guard p.terminationStatus == 0 else {
            let msg = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
            throw AppError(message: "Git 오류 또는 15초 시간 초과: \(msg.prefix(1600))")
        }
        guard result.count <= 64 * 1024 * 1024 else { throw AppError(message: "Git 응답이 64MB를 초과했습니다.") }
        return result
    }
    func run(_ args: [String]) throws -> Data { try Self.run(root, args) }
    var hasHead: Bool { (try? run(["rev-parse", "--verify", "HEAD"])) != nil }
    func list(_ mode: String) throws -> [Change] {
        let head = hasHead
        var records: [Change] = []
        if mode == "total" && !head {
            records = try fields(run(["ls-files", "--cached", "-z"])).filter { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }.map { Change(path: $0, oldPath: $0, status: "A") }
        } else {
            var args = ["diff", "--no-ext-diff", "--no-textconv", "--name-status", "-z", "-M"]
            if mode == "staged" { args.append("--cached") }
            else if mode == "total" { args.append("HEAD") }
            args.append("--")
            let values = try fields(run(args)); var i = 0
            while i < values.count {
                let status = values[i]; i += 1
                guard i < values.count else { break }; let old = values[i]; i += 1
                var path = old
                if status.hasPrefix("R") || status.hasPrefix("C") { guard i < values.count else { break }; path = values[i]; i += 1 }
                records.append(Change(path: path, oldPath: old, status: status))
            }
        }
        if mode != "staged" {
            records += try fields(run(["ls-files", "--others", "--exclude-standard", "-z"])).map { Change(path: $0, oldPath: $0, status: "?") }
        }
        let stagedPaths = Set(try fields(run(["diff", "--cached", "--name-only", "-z", "--"])))
        let workPaths = Set(try fields(run(["diff", "--name-only", "-z", "--"])))
        for i in records.indices { records[i].staged = stagedPaths.contains(records[i].path); records[i].unstaged = workPaths.contains(records[i].path) || records[i].status == "?" }
        var seen = Set<String>()
        return records.filter { (Self.markdown($0.path) || Self.markdown($0.oldPath)) && seen.insert($0.path).inserted }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
    func fields(_ data: Data) throws -> [String] {
        try data.split(separator: 0).map { part in guard let value = String(data: part, encoding: .utf8) else { throw AppError(message: "UTF-8이 아닌 파일명은 지원하지 않습니다.") }; return value }
    }
    static func markdown(_ path: String) -> Bool { ["md", "markdown", "mdown"].contains(URL(fileURLWithPath: path).pathExtension.lowercased()) }
    func safeURL(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(root.path + "/") else { throw AppError(message: "저장소 외부 파일 접근을 차단했습니다: \(path)") }; return url
    }
    func blob(_ path: String, _ version: String) throws -> Data? {
        if version == "work" {
            let url = try safeURL(path)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            guard (attrs[.size] as? NSNumber)?.intValue ?? 0 <= 16 * 1024 * 1024 else { throw AppError(message: "16MB를 넘는 파일은 표시하지 않습니다.") }
            return try Data(contentsOf: url)
        }
        if version == "head" && !hasHead { return nil }
        let listing = try run(version == "head" ? ["ls-tree", "-z", "HEAD", "--", path] : ["ls-files", "--stage", "-z", "--", path])
        guard !listing.isEmpty else { return nil }
        let mode = String(decoding: listing.prefix(6), as: UTF8.self)
        guard mode != "120000" && mode != "160000" else { throw AppError(message: "과거 시점의 심볼릭 링크/서브모듈은 읽지 않습니다: \(path)") }
        return try run(["show", (version == "head" ? "HEAD:" : ":") + path])
    }
    func text(_ path: String, _ version: String) throws -> String {
        guard let data = try blob(path, version) else { return "" }
        guard data.count <= 4 * 1024 * 1024 else { throw AppError(message: "문서가 4MB를 초과했습니다.") }
        guard !data.contains(0), let str = String(data: data, encoding: .utf8) else { throw AppError(message: "바이너리 또는 UTF-8이 아닌 문서입니다.") }; return str
    }
    func snapshot(_ change: Change, _ mode: String) throws -> Snapshot {
        let bv = mode == "unstaged" ? "index" : "head"; let av = mode == "staged" ? "index" : "work"
        let before = try text(change.oldPath, bv); let after = try text(change.path, av)
        return Snapshot(before: before, after: after, beforeLabel: bv.uppercased(), afterLabel: av.uppercased(), assets: ["before": assets(before, change.oldPath, bv), "after": assets(after, change.path, av)], error: nil)
    }
    func assets(_ text: String, _ doc: String, _ version: String) -> [String: String] {
        // Include inline, reference-style and HTML image destinations; harmless non-image destinations are ignored.
        let patterns = [#"!\[[^\]]*\]\(\s*(?:<([^>]+)>|((?:\\.|[^\s()\\]|\([^()]*\))+))(?:\s+["'][^"']*["'])?\s*\)"#, #"(?i)\bsrc\s*=\s*["']([^"']+)["']"#, #"(?m)^\s*\[[^\]]+\]:\s*(?:<([^>]+)>|([^\s]+))"#]
        var result: [String: String] = [:]
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let r = (1..<match.numberOfRanges).compactMap({ Range(match.range(at: $0), in: text) }).first else { continue }
                let src = String(text[r]).replacingOccurrences(of: #"\\([() ])"#, with: "$1", options: .regularExpression).replacingOccurrences(of: "&amp;", with: "&")
                if src.hasPrefix("https://") || src.hasPrefix("http://") { continue }
                do {
                    guard !src.contains(":"), !src.hasPrefix("/") else { throw AppError(message: "blocked") }
                    let decoded = (src.components(separatedBy: "#")[0].components(separatedBy: "?")[0]).removingPercentEncoding ?? src
                    let relative = (doc as NSString).deletingLastPathComponent + "/" + decoded
                    let url = root.appendingPathComponent(relative.hasPrefix("/") ? String(relative.dropFirst()) : relative).standardizedFileURL
                    guard url.path.hasPrefix(root.path + "/") else { throw AppError(message: "blocked") }
                    let path = String(url.path.dropFirst(root.path.count + 1))
                    let ext = url.pathExtension.lowercased(); let mime = ["png":"image/png","jpg":"image/jpeg","jpeg":"image/jpeg","gif":"image/gif","webp":"image/webp","avif":"image/avif","svg":"image/svg+xml"]
                    guard let type = mime[ext], let data = try blob(path, version), data.count <= 12 * 1024 * 1024 else { throw AppError(message: "missing") }
                    result[src] = "data:\(type);base64,\(data.base64EncodedString())"
                } catch { result[src] = "" }
            }
        }; return result
    }
}
