import Foundation
@main struct Tests {
 static var passed=0
 static func check(_ name:String,_ condition:Bool) { if !condition { fputs("FAIL: \(name)\n",stderr);exit(1) };passed += 1;print("PASS: \(name)") }
 static func main() throws {
  let fm=FileManager.default;let root=fm.temporaryDirectory.appendingPathComponent("rmd-git-"+UUID().uuidString);try fm.createDirectory(at:root,withIntermediateDirectories:true)
  defer{try? fm.removeItem(at:root)}
  func git(_ args:[String]) throws { _ = try Git.run(root,args) }
  func write(_ p:String,_ s:String) throws {let u=root.appendingPathComponent(p);try fm.createDirectory(at:u.deletingLastPathComponent(),withIntermediateDirectories:true);try s.write(to:u,atomically:true,encoding:.utf8)}
  try git(["init","-q"]);try git(["config","user.email","test@example.invalid"]);try git(["config","user.name","Test"])
  let g=try Git(root)
  try write(".gitignore","ignored.md\n");try write("ignored.md","ignored");try write("새 파일.md","새 파일");try write("개행\n문서.md","개행");try write("nested/문서.md","중첩")
  check("unborn HEAD, untracked, Korean, spaces, newline, ignored",try g.list("total").count==3)
  check("unborn staged empty",try g.list("staged").isEmpty)
  try git(["add","새 파일.md"])
  check("unborn staged initial content",try g.list("staged").count==1 && g.snapshot(g.list("staged")[0],"staged").before.isEmpty)
  try git(["add","."]);try git(["commit","-qm","initial"])
  check("clean repository",try g.list("total").isEmpty)
  try write("새 파일.md","인덱스 버전");try git(["add","새 파일.md"]);try write("새 파일.md","현재 버전")
  check("partial staging metadata",try g.list("total").first(where:{$0.path=="새 파일.md"}).map{$0.staged && $0.unstaged} == true)
  let record=try g.list("staged")[0];let stage=try g.snapshot(record,"staged"),unstage=try g.snapshot(record,"unstaged"),total=try g.snapshot(record,"total")
  check("partially staged HEAD → index",stage.before=="새 파일" && stage.after=="인덱스 버전")
  check("partially staged index → work",unstage.before=="인덱스 버전" && unstage.after=="현재 버전")
  check("total HEAD → work",total.before=="새 파일" && total.after=="현재 버전")
  try git(["mv","nested/문서.md","nested/이름 변경.md"])
  check("rename retains both paths",try g.list("staged").contains(where:{$0.status.hasPrefix("R") && $0.oldPath=="nested/문서.md" && $0.path=="nested/이름 변경.md"}))
  try fm.removeItem(at:root.appendingPathComponent("개행\n문서.md"))
  check("deletion",try g.list("total").contains(where:{$0.status=="D" && $0.path=="개행\n문서.md"}))
  try fm.createSymbolicLink(atPath:root.appendingPathComponent("escape.md").path,withDestinationPath:"/etc/passwd")
  do{_ = try g.text("escape.md","work");check("external symlink blocked",false)}catch{check("external symlink blocked",true)}
  try write("binary.md","a\0b")
  do{_ = try g.text("binary.md","work");check("binary rejected",false)}catch{check("binary rejected",true)}
  try write("image.md","![x](pixel.png)");try write("pixel.png","head-image");try git(["add","image.md","pixel.png"]);try git(["commit","-qm","image"])
  try write("pixel.png","index-image");try git(["add","pixel.png"]);try write("pixel.png","work-image")
  let a=g.assets("![x](pixel.png)","image.md","head"),b=g.assets("![x](pixel.png)","image.md","index"),c=g.assets("![x](pixel.png)","image.md","work")
  check("historical images read from distinct snapshots",a["pixel.png"] != b["pixel.png"] && b["pixel.png"] != c["pixel.png"])
  try write("now-only.png","now");check("missing historical image never falls back",g.assets("![x](now-only.png)","image.md","head")["now-only.png"]=="")
  check("external image not embedded",g.assets("![x](https://example.invalid/a.png)","image.md","head").isEmpty)
  check("traversal image blocked",g.assets("![x](../../secret.png)","image.md","work")["../../secret.png"]=="")
  try write("space (한글).png","spaces")
  check("image paths with spaces and parentheses",g.assets("![x](<space (한글).png>)","image.md","work")["space (한글).png"]?.hasPrefix("data:")==true)
  check("image reference with spaces",g.assets("![x][id]\n\n[id]: <space (한글).png>","image.md","work")["space (한글).png"]?.hasPrefix("data:")==true)
  let wt=fm.temporaryDirectory.appendingPathComponent("rmd-worktree-"+UUID().uuidString);defer{try? fm.removeItem(at:wt)}
  try git(["worktree","add","--detach",wt.path,"HEAD"])
  let work=try Git(wt);check("linked worktree .git file supported",work.root.path==wt.path && work.hasHead)
  try write(":(glob)*.md","literal");try git(["add","--",":(glob)*.md"])
  check("literal pathspec filename",try g.text(":(glob)*.md","index")=="literal")
  try commitComparisons()
  print("GIT TESTS: \(passed) passed")
 }
 static func commitComparisons() throws {
  let fm=FileManager.default,root=FileManager.default.temporaryDirectory.appendingPathComponent("rmd-commit-"+UUID().uuidString)
  try fm.createDirectory(at:root,withIntermediateDirectories:true);defer{try? fm.removeItem(at:root)}
  func git(_ args:[String]) throws {_ = try Git.run(root,args)}
  func write(_ path:String,_ value:String) throws {let file=root.appendingPathComponent(path);try fm.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true);try value.write(to:file,atomically:true,encoding:.utf8)}
  try git(["init","-q"]);try git(["config","user.name","Test"]);try git(["config","user.email","test@example.invalid"])
  let g=try Git(root)
  check("unborn commit history is empty",try g.commits().isEmpty)
  do{_ = try g.list("commit");check("missing custom baseline rejected",false)}catch{check("missing custom baseline rejected",true)}
  try write(".gitignore","ignored.md\n");try write("기록.md","초안");try write("삭제.md","삭제 전");try write("복원.md","원래 내용")
  try write("이전 위치/문서.md","# 이미지\n\n![x](pixel.png)");try write("이전 위치/pixel.png","original-image")
  try git(["add","."]);try git(["commit","-qm","기준\t커밋 · 한글 \"인용\""])
  let base=try g.resolveCommit("HEAD")
  check("history contains UTF-8 subject and full SHA",try g.commits().first?.id==base && g.commits().first?.subject.contains("한글 \"인용\"")==true)
  try git(["tag","-a","comparison-base","-m","baseline",base])
  check("short hashes and annotated tags resolve to a commit",try g.resolveCommit(String(base.prefix(8)))==base && g.resolveCommit("comparison-base")==base)
  try write("기록.md","커밋된 변경");try write("추가.md","커밋된 새 문서")
  try git(["rm","삭제.md","복원.md"]);try git(["mv","이전 위치","새 위치"]);try write("새 위치/pixel.png","committed-image")
  try git(["add","."]);try git(["commit","-qm","second"])
  try git(["commit","--allow-empty","--allow-empty-message","-qm",""])
  check("history retains empty commit subjects",try g.commits().first?.subject=="")
  check("commit list limit and parent references",try g.commits(limit:1).count==1 && g.resolveCommit("HEAD~2")==base)
  try write("기록.md","스테이징된 변경");try git(["add","기록.md"]);try write("기록.md","현재 작업 내용")
  try write("새 위치/pixel.png","working-image");try write("신규 문서.md","새 문서");try write("ignored.md","ignore")
  let files=try g.list("commit",baseCommit:base)
  let record=files.first(where:{$0.path=="기록.md"})!
  let snapshot=try g.snapshot(record,"commit",baseCommit:base)
  check("custom comparison includes committed and working changes",snapshot.before=="초안" && snapshot.after=="현재 작업 내용")
  check("custom baseline has a stable full commit version",snapshot.beforeVersion=="COMMIT:"+base && snapshot.beforeLabel.contains(String(base.prefix(12))))
  check("custom comparison includes untracked and excludes ignored",files.contains(where:{$0.path=="신규 문서.md"}) && !files.contains(where:{$0.path=="ignored.md"}))
  check("custom comparison shows committed addition and deletion",files.contains(where:{$0.path=="추가.md" && $0.status=="A"}) && files.contains(where:{$0.path=="삭제.md" && $0.status=="D"}))
  let renamed=files.first(where:{$0.path=="새 위치/문서.md"})!
  check("custom baseline retains rename paths",renamed.oldPath=="이전 위치/문서.md" && renamed.status.hasPrefix("R"))
  let image=try g.snapshot(renamed,"commit",baseCommit:base)
  check("custom baseline images use original path and commit bytes",image.assets["before"]?["pixel.png"]=="data:image/png;base64,"+Data("original-image".utf8).base64EncodedString() && image.assets["after"]?["pixel.png"]=="data:image/png;base64,"+Data("working-image".utf8).base64EncodedString())
  try git(["tag","-f","comparison-base","HEAD"])
  check("resolved commit remains pinned when a reference moves",try g.resolveCommit("comparison-base") != base && g.snapshot(record,"commit",baseCommit:base).before=="초안")
  try write("복원.md","원래 내용")
  check("recreated untracked path equal to old commit is unchanged",try !g.list("commit",baseCommit:base).contains(where:{$0.path=="복원.md"}))
  try write("복원.md","다시 쓴 내용")
  check("recreated untracked baseline path is modified, not deleted",try g.list("commit",baseCommit:base).first(where:{$0.path=="복원.md"}).map{$0.status=="M" && $0.unstaged}==true)
  let blob=String(decoding:try g.run(["hash-object","-w","기록.md"]),as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
  for input in ["does-not-exist","--output="+root.appendingPathComponent("unexpected").path,blob,"\0",""] {
   do{_ = try g.resolveCommit(input);check("invalid or non-commit reference rejected",false)}catch{check("invalid or non-commit reference rejected",true)}
  }
  check("option-like revision does not write a file",!fm.fileExists(atPath:root.appendingPathComponent("unexpected").path))
 }

}
