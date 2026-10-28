import Foundation
import CryptoKit

enum CommentStatus: String, Codable { case pending, inProgress, resolved }

struct ReviewComment: Codable {
    var id: String
    var repository: String
    var document: String
    var file: String
    var side: String
    var version: String
    var startLine: Int
    var endLine: Int
    var excerpt: String
    var body: String
    var sourceHash: String
    var createdAt: String
    var status: CommentStatus = .pending
    enum CodingKeys: String, CodingKey {
        case id, repository, document, file, side, version, startLine, endLine, excerpt, body, sourceHash, createdAt, status
    }
}
extension ReviewComment {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        repository = try c.decode(String.self, forKey: .repository)
        document = try c.decode(String.self, forKey: .document)
        file = try c.decode(String.self, forKey: .file)
        side = try c.decode(String.self, forKey: .side)
        version = try c.decode(String.self, forKey: .version)
        startLine = try c.decode(Int.self, forKey: .startLine)
        endLine = try c.decode(Int.self, forKey: .endLine)
        excerpt = try c.decode(String.self, forKey: .excerpt)
        body = try c.decode(String.self, forKey: .body)
        sourceHash = try c.decode(String.self, forKey: .sourceHash)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        status = try c.decodeIfPresent(CommentStatus.self, forKey: .status) ?? .pending
    }
}
struct ReviewDocument {
    var repository: String; var document: String; var oldPath: String
    var before: String; var after: String; var beforeVersion: String; var afterVersion: String
    var id: String { Self.hash(repository + "\0" + document + "\0" + oldPath + "\0" + beforeVersion + "\0" + afterVersion + "\0" + before + "\0" + after) }
    static func hash(_ source: String) -> String { SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined() }
    static func lines(_ source: String) -> [String] { source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n") }
    func makeComment(side: String, start: Int, end: Int, body: String) throws -> ReviewComment {
        guard ["before", "after"].contains(side) else { throw AppError(message: "비교 대상을 다시 선택하세요.") }
        let source = side == "before" ? before : after
        let lines = Self.lines(source)
        guard !source.isEmpty, start >= 1, end >= start, end <= lines.count else { throw AppError(message: "유효한 원문 라인 범위를 선택하세요.") }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, body.utf8.count <= 40000 else { throw AppError(message: "코멘트를 입력하세요. 최대 크기는 40KB입니다.") }
        return ReviewComment(id: UUID().uuidString, repository: repository, document: document, file: side == "before" ? oldPath : document, side: side, version: side == "before" ? beforeVersion : afterVersion, startLine: start, endLine: end, excerpt: lines[(start - 1)...(end - 1)].joined(separator: "\n"), body: trimmed, sourceHash: Self.hash(source), createdAt: ISO8601DateFormatter().string(from: Date()))
    }
}
func exportComment(_ comment: ReviewComment) -> String {
    let range = comment.startLine == comment.endLine ? "\(comment.startLine)" : "\(comment.startLine)-\(comment.endLine)"
    let excerpt = comment.excerpt.components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n")
    let quoted = (try? JSONSerialization.data(withJSONObject: comment.body, options: [.fragmentsAllowed, .withoutEscapingSlashes])).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    return "File: \(comment.file)\nSource: markdown\n\nLines \(range)\nExcerpt:\n\(excerpt)\nUser comment: \(quoted)"
}
final class CommentStore {
    let url: URL
    private var values: [ReviewComment] = []
    private var loadError: Error?
    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Rich Markdown Diff/comments.json")
        if FileManager.default.fileExists(atPath: self.url.path) {
            do { values = try JSONDecoder().decode([ReviewComment].self, from: Data(contentsOf: self.url)) }
            catch { loadError = AppError(message: "저장된 코멘트를 읽지 못했습니다. 기존 파일은 덮어쓰지 않습니다: \(error.localizedDescription)") }
        }
    }
    var errorMessage: String? { loadError?.localizedDescription }
    func comments(repository: String, document: String) -> [ReviewComment] { values.filter { $0.repository == repository && $0.document == document } }
    private func save(_ next: [ReviewComment]) throws {
        if let error = loadError { throw error }
        let data = try JSONEncoder().encode(next)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        values = next
    }
    func add(_ comment: ReviewComment) throws { try save(values + [comment]) }
    func edit(id: String, repository: String, document: String, body: String) throws {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, body.utf8.count <= 40000 else { throw AppError(message: "코멘트는 비어 있을 수 없으며 최대 크기는 40KB입니다.") }
        guard let index = values.firstIndex(where: { $0.id == id && $0.repository == repository && $0.document == document }) else { throw AppError(message: "코멘트를 찾지 못했습니다.") }
        var next = values; next[index].body = text; try save(next)
    }
    func resolve(id: String, repository: String, document: String) throws {
        guard let index = values.firstIndex(where: { $0.id == id && $0.repository == repository && $0.document == document }) else { throw AppError(message: "코멘트를 찾지 못했습니다.") }
        if values[index].status == .resolved { return }
        var next = values; next[index].status = .resolved; try save(next)
    }
    @discardableResult
    func copy(id: String? = nil, repository: String, document: String, writeClipboard: (String) -> Bool) throws -> Int {
        let scope = comments(repository: repository, document: document)
        let chosen = id.map { selected in scope.filter { $0.id == selected } } ?? scope
        guard !chosen.isEmpty else { throw AppError(message: "복사할 코멘트가 없습니다.") }
        if let error = loadError { throw error }
        let text = chosen.map(exportComment).joined(separator: "\n\n")
        guard writeClipboard(text) else { throw AppError(message: "클립보드에 복사하지 못했습니다.") }
        var next = values
        for index in next.indices where next[index].repository == repository && next[index].document == document {
            if let id {
                if next[index].id == id { next[index].status = .inProgress }
                else if next[index].status != .resolved { next[index].status = .pending }
            } else if next[index].status != .resolved { next[index].status = .inProgress }
        }
        do { try save(next) }
        catch { throw AppError(message: "텍스트는 복사했지만 코멘트 상태를 저장하지 못했습니다: \(error.localizedDescription)") }
        return chosen.count
    }
    func delete(id: String, repository: String, document: String) throws {
        try save(values.filter { !($0.id == id && $0.repository == repository && $0.document == document) })
    }
}
