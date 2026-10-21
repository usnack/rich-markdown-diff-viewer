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
  print("GIT TESTS: \(passed) passed")
 }
}
