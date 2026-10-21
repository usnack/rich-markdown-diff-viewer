import Foundation
import WebKit
// Opt-in verification harness. Writes only the generated fixture with its marker; never a user's repository.
extension App {
    func evaluate(_ code: String) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            web.callAsyncJavaScript(code, arguments: [:], in: nil, in: .page) { continuation.resume(with: $0) }
        }
    }
    func runWorkflowVerification() {
        guard let output = verifyPath, let repo, FileManager.default.fileExists(atPath: repo.appendingPathComponent(".rmd-demo").path), repo.resolvingSymlinksInPath().path == URL(fileURLWithPath: output).appendingPathComponent("demo").resolvingSymlinksInPath().path else { return }
        Task { @MainActor in
            let doc = repo.appendingPathComponent("01-제품 설계.md")
            guard let original = try? Data(contentsOf: doc), let git = try? Git(repo), let indexed = try? git.blob("01-제품 설계.md", "index") else { return }
            var report: [String: Any] = [:]
            do {
                report["start"] = try await evaluate("return window.workflowStart()")
                try await Task.sleep(nanoseconds: 500_000_000)
                var updated = Data("# 자동 갱신 검증용 추가 문단\n\n".utf8); updated.append(original)
                try updated.write(to: doc, options: .atomic)
                try await Task.sleep(nanoseconds: 3_000_000_000)
                report["paused"] = try await evaluate("return window.workflowPaused()")
                _ = try await evaluate("return window.workflowResume()")
                try await Task.sleep(nanoseconds: 3_000_000_000)
                report["resumed"] = try await evaluate("return window.workflowAfter()")
                report["rapidSelection"] = try await evaluate("return await window.workflowRapid()")
                _ = try await evaluate("return window.workflowIndexStart()")
                try await Task.sleep(nanoseconds: 2_000_000_000)
                _ = try git.run(["add", "--", "01-제품 설계.md"])
                try await Task.sleep(nanoseconds: 3_000_000_000)
                report["indexRefresh"] = try await evaluate("return window.workflowIndexCheck()")
                // Restore both fixture versions exactly; never touch other repositories.
                try indexed.write(to: doc, options: .atomic); _ = try git.run(["add", "--", "01-제품 설계.md"]); try original.write(to: doc, options: .atomic)
                _ = try await evaluate("return window.workflowEnd()")
                try await Task.sleep(nanoseconds: 3_000_000_000)
                report["restored"] = true
            } catch { report["error"] = error.localizedDescription; try? indexed.write(to: doc); _ = try? git.run(["add", "--", "01-제품 설계.md"]); try? original.write(to: doc) }
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: URL(fileURLWithPath: output + "/workflow-results.json")) }
            web.takeSnapshot(with: nil) { image, _ in
                if let tiff = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: output + "/app-screen.png")) }
            }
        }
    }
}
