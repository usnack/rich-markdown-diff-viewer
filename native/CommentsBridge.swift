import AppKit
import WebKit
extension App {
    func commentPayload(repository: String, document: String) -> [String: Any] {
        let comments = commentStore.comments(repository: repository, document: document)
        return ["comments": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(comments))) ?? [], "commentsError": commentStore.errorMessage ?? ""]
    }
    func pushComments() {
        guard let review else { return }
        var data = commentPayload(repository: review.repository, document: review.document); data["context"] = review.id
        if let encoded = try? JSONSerialization.data(withJSONObject: data), let json = String(data: encoded, encoding: .utf8) { web.evaluateJavaScript("window.receiveComments(\(json))", completionHandler: nil) }
    }
    func handleComment(_ action: String, _ input: [String: Any]) {
        var result: [String: Any] = ["action": action, "ok": false, "context": input["context"] as? String ?? "", "id": input["id"] as? String ?? ""]
        do {
            guard let review, input["context"] as? String == review.id else { throw AppError(message: "문서가 변경되었습니다. 원문 라인을 다시 선택한 뒤 시도하세요.") }
            let id = input["id"] as? String ?? ""
            switch action {
            case "commentAdd":
                guard let side = input["side"] as? String, let start = input["startLine"] as? Int, let end = input["endLine"] as? Int, let body = input["body"] as? String else { throw AppError(message: "코멘트 입력을 확인하세요.") }
                let comment = try review.makeComment(side: side, start: start, end: end, body: body)
                try commentStore.add(comment); result["id"] = comment.id
            case "commentEdit": try commentStore.edit(id: id, repository: review.repository, document: review.document, body: input["body"] as? String ?? "")
            case "commentDelete": try commentStore.delete(id: id, repository: review.repository, document: review.document)
            case "commentCopy", "commentsCopy":
                let all = commentStore.comments(repository: review.repository, document: review.document)
                let chosen = action == "commentsCopy" ? all : all.filter { $0.id == id }
                guard !chosen.isEmpty else { throw AppError(message: "복사할 코멘트가 없습니다.") }
                let text = chosen.map(exportComment).joined(separator: "\n\n")
                NSPasteboard.general.clearContents()
                guard NSPasteboard.general.setString(text, forType: .string) else { throw AppError(message: "클립보드에 복사하지 못했습니다.") }
                result["count"] = chosen.count
            default: return
            }
            result["ok"] = true
            pushComments()
        } catch { result["error"] = error.localizedDescription }
        if let data = try? JSONSerialization.data(withJSONObject: result), let json = String(data: data, encoding: .utf8) { web.evaluateJavaScript("window.receiveCommentResult(\(json))", completionHandler: nil) }
    }
}
