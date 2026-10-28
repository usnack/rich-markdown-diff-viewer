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
  try statusTransitions(root:root,doc:doc)
  print("COMMENT TESTS: \(n) passed")
 }
 static func statusTransitions(root:URL,doc:ReviewDocument) throws {
  let url=root.appendingPathComponent("states.json"),store=CommentStore(url:root.appendingPathComponent("states.json"))
  let a=try doc.makeComment(side:"after",start:1,end:1,body:"alpha"),b=try doc.makeComment(side:"after",start:2,end:2,body:"beta"),c=try doc.makeComment(side:"after",start:3,end:3,body:"gamma")
  var other=try doc.makeComment(side:"after",start:1,end:1,body:"other document");other.document="other.md";other.status = .inProgress
  var foreign=try doc.makeComment(side:"after",start:1,end:1,body:"other repository");foreign.repository="/other";foreign.status = .inProgress
  for item in [a,b,c,other,foreign]{try store.add(item)}
  func items()->[ReviewComment]{store.comments(repository:doc.repository,document:doc.document)}
  func state(_ id:String)->CommentStatus{items().first(where:{$0.id==id})!.status}
  check("new comments start pending",items().allSatisfy{$0.status == .pending})
  var copied=""
  let first=try store.copy(id:a.id,repository:doc.repository,document:doc.document){copied=$0;return true}
  check("individual copy progresses only selected comment",first==1 && state(a.id) == .inProgress && state(b.id) == .pending && state(c.id) == .pending)
  check("status never changes exported comment format",copied==exportComment(a))
  try store.copy(id:b.id,repository:doc.repository,document:doc.document){_ in true}
  check("latest individual copy resets previous unfinished comment",state(a.id) == .pending && state(b.id) == .inProgress)
  try store.resolve(id:a.id,repository:doc.repository,document:doc.document)
  check("resolve marks only chosen comment completed",state(a.id) == .resolved && state(b.id) == .inProgress)
  try store.copy(repository:doc.repository,document:doc.document){copied=$0;return true}
  check("copy all progresses unfinished and preserves completed",state(a.id) == .resolved && state(b.id) == .inProgress && state(c.id) == .inProgress)
  check("copy all retains all comments in original order",copied==[a,b,c].map(exportComment).joined(separator:"\n\n"))
  try store.resolve(id:c.id,repository:doc.repository,document:doc.document)
  try store.copy(id:a.id,repository:doc.repository,document:doc.document){_ in true}
  check("copying completed comment reopens only it",state(a.id) == .inProgress && state(b.id) == .pending && state(c.id) == .resolved)
  check("copy and resolve do not affect other documents or repositories",store.comments(repository:doc.repository,document:"other.md")[0].status == .inProgress && store.comments(repository:"/other",document:doc.document)[0].status == .inProgress)
  try store.edit(id:c.id,repository:doc.repository,document:doc.document,body:"edited")
  check("editing preserves completed status",state(c.id) == .resolved)
  let before=try Data(contentsOf:url)
  do{try store.copy(id:b.id,repository:doc.repository,document:doc.document){_ in false};check("failed clipboard write leaves status unchanged",false)}catch{let after=try Data(contentsOf:url);check("failed clipboard write leaves status unchanged",state(a.id) == .inProgress && state(b.id) == .pending && after==before)}
  var invoked=false
  do{try store.copy(id:other.id,repository:doc.repository,document:doc.document){_ in invoked=true;return true};check("cross-document copy rejected before clipboard write",false)}catch{check("cross-document copy rejected before clipboard write",!invoked)}
  do{try store.resolve(id:other.id,repository:doc.repository,document:doc.document);check("cross-document resolve rejected",false)}catch{check("cross-document resolve rejected",true)}
  let reloaded=CommentStore(url:url).comments(repository:doc.repository,document:doc.document)
  check("statuses survive store reload",reloaded.map{$0.status} == [.inProgress,.pending,.resolved])
  var legacy=try JSONSerialization.jsonObject(with:JSONEncoder().encode([a,b])) as! [[String:Any]]
  for i in legacy.indices{legacy[i].removeValue(forKey:"status")}
  let legacyURL=root.appendingPathComponent("legacy.json");try JSONSerialization.data(withJSONObject:legacy).write(to:legacyURL)
  let old=CommentStore(url:legacyURL).comments(repository:doc.repository,document:doc.document)
  check("legacy comments without status load as pending",old.count==2 && old.allSatisfy{$0.status == .pending} && old[0].body==a.body && old[0].id==a.id)
  try FileManager.default.removeItem(at:url);try FileManager.default.createDirectory(at:url,withIntermediateDirectories:false)
  var wrote=false
  do{try store.copy(id:b.id,repository:doc.repository,document:doc.document){_ in wrote=true;return true};check("persistence failure reported after clipboard success",false)}catch{check("persistence failure reported after clipboard success",wrote && error.localizedDescription.contains("복사했지만") && state(a.id) == .inProgress && state(b.id) == .pending)}
 }

}
