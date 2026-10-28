import AppKit
import WebKit

final class App: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    var window: NSWindow!; var web: WKWebView!
    var repo: URL?; var selected = ""; var mode = "total"; var layout = "unified"; var only = false; var paused = false
    var commitBases: [String: String] = [:]
    var generation = 0; var busy = false; var lastPayload = ""; var timer: Timer?
    let queue = DispatchQueue(label: "richdiff.git", qos: .userInitiated)
    let defaults = UserDefaults.standard
    lazy var commentStore = CommentStore()
    var review: ReviewDocument?
    let world = WKContentWorld.world(name: "RichDiffBridge")
    var verifyPath: String?; var verificationStarted = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--verify"), args.count > i + 1 { verifyPath = args[i + 1] }
        if let verifyPath { commentStore = CommentStore(url: URL(fileURLWithPath: verifyPath).appendingPathComponent("test-comments.json")) }
        if let p = defaults.string(forKey: "repo") { repo = URL(fileURLWithPath: p) }
        commitBases = defaults.dictionary(forKey: "comparisonCommits") as? [String: String] ?? [:]
        selected = defaults.string(forKey: "selected") ?? ""; mode = defaults.string(forKey: "mode") ?? "total"; layout = defaults.string(forKey: "layout") ?? "unified"; only = defaults.bool(forKey: "only")
        if verifyPath != nil { mode = "total" }
        if let i = args.firstIndex(of: "--repo"), args.count > i + 1 { repo = URL(fileURLWithPath: args[i + 1]); selected = "" }
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, contentWorld: world, name: "native")
        let bridge = """
        document.addEventListener('rmd-command', e => {
          if(e.target !== document) return;
          try { window.webkit.messageHandlers.native.postMessage(JSON.parse(e.detail)); } catch(_) {}
        });
        """
        config.userContentController.addUserScript(WKUserScript(source: bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world))
        web = WKWebView(frame: .zero, configuration: config); web.navigationDelegate = self
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 850), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Rich Markdown Diff"; window.minSize = NSSize(width: 900, height: 600); window.contentView = web; window.center(); window.makeKeyAndOrderFront(nil)
        let menu = NSMenu(); let appItem = NSMenuItem(); menu.addItem(appItem); let submenu = NSMenu(); submenu.addItem(withTitle: "저장소 열기…", action: #selector(openRepo), keyEquivalent: "o"); submenu.addItem(.separator()); submenu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); appItem.submenu = submenu
        let editItem = NSMenuItem(title: "편집", action: nil, keyEquivalent: ""); let edit = NSMenu(title: "편집")
        for (title, selector, key) in [("실행 취소", "undo:", "z"), ("잘라내기", "cut:", "x"), ("복사", "copy:", "c"), ("붙여넣기", "paste:", "v"), ("전체 선택", "selectAll:", "a")] { edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key) }
        editItem.submenu = edit; menu.addItem(editItem); NSApp.mainMenu = menu
        guard let resources = Bundle.main.resourceURL else { return }
        web.loadFileURL(resources.appendingPathComponent("index.html"), allowingReadAccessTo: resources)
        timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in self?.refresh() }
        NSApp.activate(ignoringOtherApps: true)
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let path = filenames.first else { sender.reply(toOpenOrPrint: .failure); return }
        openTarget(URL(fileURLWithPath: path)); sender.reply(toOpenOrPrint: .success)
    }
    func openTarget(_ target: URL) {
        invalidate(); let token = generation
        queue.async {
            var directory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: target.path, isDirectory: &directory)
            let folder = directory.boolValue ? target : target.deletingLastPathComponent()
            do {
                guard exists else { throw AppError(message: "경로가 존재하지 않습니다: \(target.path)") }
                let git = try Git(folder)
                let file = target.standardizedFileURL.resolvingSymlinksInPath()
                let path = directory.boolValue ? "" : String(file.path.dropFirst(git.root.path.count + 1))
                guard directory.boolValue || (file.path.hasPrefix(git.root.path + "/") && Git.markdown(path)) else { throw AppError(message: "Git 저장소 폴더 또는 Markdown 파일을 선택하세요.") }
                DispatchQueue.main.async {
                    guard token == self.generation else { return }
                    self.repo = git.root; self.selected = path; self.invalidate(); self.refresh(force: true)
                }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async {
                    guard token == self.generation else { return }
                    self.repo = folder; self.selected = ""; self.invalidate()
                    self.send(["files": [], "repo": folder.path, "selected": "", "mode": self.mode, "layout": self.layout, "only": self.only, "error": message])
                }
            }
        }
    }
    func selectCommit(_ revision: String, request: String) {
        guard let repo else { return }
        invalidate(); let token = generation
        queue.async {
            var response: [String: Any] = ["request": request, "repo": repo.path, "ok": false]
            var resolved = ""; var root = repo
            do {
                let git = try Git(repo); root = git.root; resolved = try git.resolveCommit(revision)
                response["ok"] = true; response["commit"] = resolved
            } catch { response["error"] = error.localizedDescription }
            let result = response; let commit = resolved; let finalRoot = root
            DispatchQueue.main.async {
                guard token == self.generation else { return }
                if !commit.isEmpty { self.repo = finalRoot; self.commitBases[finalRoot.path] = commit; self.mode = "commit"; self.persist() }
                if let data = try? JSONSerialization.data(withJSONObject: result), let json = String(data: data, encoding: .utf8) { self.web.evaluateJavaScript("window.receiveCommitResult(\(json))", completionHandler: nil) }
                self.invalidate(); self.refresh(force: true)
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    @objc func openRepo() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; panel.prompt = "저장소 열기"
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url { self.repo = url; self.selected = ""; self.invalidate(); self.refresh(force: true) }
        }
    }
    func invalidate() { generation += 1; lastPayload = "" }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let data = message.body as? [String: Any], let action = data["action"] as? String else { return }
        switch action {
        case "ready": refresh(force: true)
        case "open": openRepo()
        case "file": if let value = data["value"] as? String { selected = value; invalidate(); refresh(force: true) }
        case "mode": if let value = data["value"] as? String, ["total", "unstaged", "staged", "commit"].contains(value) { mode = value; invalidate(); refresh(force: true) }
        case "commit": if let input = data["value"] as? [String: Any], let value = input["revision"] as? String, let request = input["request"] as? String { selectCommit(value, request: request) }
        case "layout": if let value = data["value"] as? String, ["unified", "split"].contains(value) { layout = value; persist() }
        case "only": only = data["value"] as? Bool ?? false; persist()
        case "pause": paused = data["value"] as? Bool ?? false; if !paused { invalidate(); refresh(force: true) }
        case "commentAdd", "commentEdit", "commentDelete", "commentResolve", "commentCopy", "commentsCopy":
            if let input = data["value"] as? [String: Any] { handleComment(action, input) }
        case "external": if let s = data["value"] as? String, let url = URL(string: s), ["https", "http"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
        default: break
        }
    }
    func persist() { defaults.set(repo?.path, forKey: "repo"); defaults.set(selected, forKey: "selected"); defaults.set(mode, forKey: "mode"); defaults.set(layout, forKey: "layout"); defaults.set(only, forKey: "only"); defaults.set(commitBases, forKey: "comparisonCommits") }
    func send(_ original: [String: Any]) {
        var payload = original
        if let root = payload["repo"] as? String, let file = payload["selected"] as? String {
            let comments = commentPayload(repository: root, document: file)
            for (key, value) in comments { payload[key] = value }
            if let snapshot = payload["snapshot"] as? [String: Any], let before = snapshot["before"] as? String, let after = snapshot["after"] as? String {
                let files = payload["files"] as? [[String: Any]] ?? []
                let old = files.first(where: { ($0["path"] as? String) == file })?["oldPath"] as? String ?? file
                review = ReviewDocument(repository: root, document: file, oldPath: old, before: before, after: after, beforeVersion: snapshot["beforeVersion"] as? String ?? snapshot["beforeLabel"] as? String ?? "", afterVersion: snapshot["afterLabel"] as? String ?? "")
                payload["commentContext"] = review?.id
            } else {
                review = ReviewDocument(repository: root, document: file, oldPath: file, before: "", after: "", beforeVersion: "", afterVersion: "")
                payload["commentContext"] = review?.id
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]), let json = String(data: data, encoding: .utf8), json != lastPayload else { return }
        lastPayload = json
        web.evaluateJavaScript("window.receive(\(json))") { _, error in
            if let error { NSLog("Renderer: %@", error.localizedDescription) }
        }
    }
    func refresh(force: Bool = false) {
        guard (!paused || force), !busy else { return }
        guard let repo else { send(["files": [], "repo": "", "selected": "", "mode": mode, "layout": layout, "only": only]); return }
        busy = true
        let token = generation; let currentMode = mode; let currentSelected = selected; let bases = commitBases
        queue.async {
            var payload: [String: Any] = [:]; var selection = currentSelected; var root = repo
            do {
                let git = try Git(repo); root = git.root
                let base = bases[root.path] ?? ""
                payload["baseCommit"] = base
                if currentMode == "commit" {
                    do { payload["commits"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(git.commits())) }
                    catch { payload["commits"] = []; payload["historyError"] = error.localizedDescription }
                }
                let needsCommit = currentMode == "commit" && base.isEmpty
                let files = needsCommit ? [] : try git.list(currentMode, baseCommit: base)
                if needsCommit { payload["chooseCommit"] = true }
                if selection.isEmpty { selection = files.first?.path ?? "" }
                payload["files"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(files))
                if let change = files.first(where: { $0.path == selection }) {
                    selection = change.path
                    do { payload["snapshot"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(git.snapshot(change, currentMode, baseCommit: base))) }
                    catch { payload["error"] = error.localizedDescription }
                } else if !selection.isEmpty && !needsCommit { payload["missing"] = true }
            } catch { payload["error"] = error.localizedDescription; payload["files"] = [] }
            let result = payload; let finalSelection = selection; let finalRoot = root
            DispatchQueue.main.async {
                self.busy = false
                guard token == self.generation else { self.refresh(force: true); return }
                guard !self.paused || force else { return }
                self.repo = finalRoot; self.selected = finalSelection; self.persist()
                var p = result; p["repo"] = finalRoot.path; p["selected"] = finalSelection; p["mode"] = currentMode; p["layout"] = self.layout; p["only"] = self.only
                self.send(p)
                if self.verifyPath != nil && !self.verificationStarted { self.verificationStarted = true; self.runVerification() }
            }
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated { if let url = navigationAction.request.url, ["https", "http"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }; decisionHandler(.cancel) }
        else { decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel) }
    }
    func runVerification() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            let verificationCode = CommandLine.arguments.contains("--inspect-review") ? "return await window.inspectReviewSelection()" : "return await window.verifyApp()"
            self.web.callAsyncJavaScript(verificationCode, arguments: [:], in: nil, in: .page) { result in
                guard let path = self.verifyPath else { return }
                var output: Any
                switch result { case .success(let value):
                    var report = value as? [String: Any] ?? [:]
                    if let review = self.review {
                        let expected = self.commentStore.comments(repository: review.repository, document: review.document).map(exportComment).joined(separator: "\n\n")
                        let copied = NSPasteboard.general.string(forType: .string) ?? ""
                        report["nativeClipboardCheck"] = !expected.isEmpty && copied == expected
                        report["clipboardText"] = copied
                    }
                    output = report; case .failure(let error): output = ["fatal": error.localizedDescription] }
                if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: URL(fileURLWithPath: path + "/app-results.json")) }
                if !CommandLine.arguments.contains("--inspect-review") { self.runWorkflowVerification() }
                self.web.takeSnapshot(with: nil) { image, _ in
                    if let tiff = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path + "/app-screen.png")) }
                }
            }
        }
    }
}
let application = NSApplication.shared
let delegate = App(); application.delegate = delegate; application.setActivationPolicy(.regular); application.run()
