import Foundation
@main struct CommentTests {
 static var n=0
 static func check(_ name:String,_ value:Bool){guard value else{fputs("FAIL: \(name)\n",stderr);exit(1)};n+=1;print("PASS: \(name)")}
 static func main() throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("rmd-comments-"+UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
  let url=root.appendingPathComponent("comments.json"),store=CommentStore(url:root.appendingPathComponent("comments.json"))
  let raw=(1...12).map{ "line \($0)" }.joined(separator:"\n")
  let doc=ReviewDocument(repository:"/repo",document:"02-단원/문서.md",oldPath:"old/문서.md",before:"old\r\nline",after:raw,beforeVersion:"HEAD",afterVersion:"WORK")
  let comment=try doc.makeComment(side:"after",start:7,end:10,body:"asdf")
  let expected="File: 02-단원/문서.md\nSource: markdown\n\nLines 7-10\nExcerpt:\n> line 7\n> line 8\n> line 9\n> line 10\nUser comment: \"asdf\""
  check("exact requested export format",exportComment(comment)==expected)
  try store.add(comment);try store.add(doc.makeComment(side:"after",start:7,end:10,body:"second"))
  check("multiple comments on same range",store.comments(repository:"/repo",document:doc.document).count==2)
  let reloaded=CommentStore(url:url);check("comments survive reloading",reloaded.comments(repository:"/repo",document:doc.document).count==2)
  check("repository and document scopes isolated",store.comments(repository:"/other",document:doc.document).isEmpty && store.comments(repository:"/repo",document:"other.md").isEmpty)
  try store.edit(id:comment.id,repository:"/repo",document:doc.document,body:"a \"quote\"\nnext")
  let edited=store.comments(repository:"/repo",document:doc.document)[0]
  check("quoted and multiline body escaped",exportComment(edited).hasSuffix("User comment: \"a \\\"quote\\\"\\nnext\""))
  check("editing preserves excerpt and range",edited.excerpt==comment.excerpt && edited.startLine==7 && edited.endLine==10)
  let old=try doc.makeComment(side:"before",start:1,end:2,body:"old side")
  check("before-side rename and CRLF",old.file=="old/문서.md" && old.version=="HEAD" && old.excerpt=="old\nline")
  for range in [(0,1),(1,13),(10,7)]{do{_=try doc.makeComment(side:"after",start:range.0,end:range.1,body:"x");check("invalid range rejected",false)}catch{check("invalid range rejected",true)}}
  do{_=try doc.makeComment(side:"after",start:1,end:1,body:" \n ");check("blank body rejected",false)}catch{check("blank body rejected",true)}
  try store.delete(id:comment.id,repository:"/repo",document:doc.document);check("delete affects only chosen comment",store.comments(repository:"/repo",document:doc.document).count==1)
  try Data("broken".utf8).write(to:url);let broken=CommentStore(url:url)
  do{try broken.add(comment);check("corrupt storage preserved",false)}catch{check("corrupt storage preserved",try Data(contentsOf:url)==Data("broken".utf8))}
  check("context changes when either source changes",doc.id != ReviewDocument(repository:"/repo",document:doc.document,oldPath:doc.oldPath,before:doc.before,after:raw+"!",beforeVersion:"HEAD",afterVersion:"WORK").id)
  print("COMMENT TESTS: \(n) passed")
 }
}
