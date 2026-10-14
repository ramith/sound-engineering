import Foundation
let fm = FileManager.default
let t = fm.temporaryDirectory.path
print("tempdir:", t)
func std(_ p: String) -> String { ((p as NSString).expandingTildeInPath as NSString).standardizingPath }
for p in ["/private/tmp", "/private/tmp/p5a-nonexistent-xyz", "/private/var/folders", t, "/private" + t, "/private" + t + "nope", "/Users/../Users/./ramith//Music/", "~/Music"] {
  print("standardizingPath(\(p)) = \(std(p))")
}
// symlink + ..
let base = t + "p5a-pn-" + UUID().uuidString
try! fm.createDirectory(atPath: base + "/real/sub", withIntermediateDirectories: true)
try! fm.createSymbolicLink(atPath: base + "/link", withDestinationPath: base + "/real/sub")
fm.createFile(atPath: base + "/real/f.flac", contents: Data())
print("link/../f.flac ->", std(base + "/link/../f.flac"), " (lexical would be", base + "/f.flac)")
print("URL.standardizedFileURL:", URL(fileURLWithPath: base + "/link/../f.flac").standardizedFileURL.path)
print("URL std /private/tmp:", URL(fileURLWithPath: "/private/tmp/x").standardizedFileURL.path, URL(fileURLWithPath: "/private/tmp").standardizedFileURL.path)
// enumerator path form
let e = fm.enumerator(at: URL(fileURLWithPath: base + "/real"), includingPropertiesForKeys: nil)!
while let u = e.nextObject() as? URL { print("enum:", u.path) }
let e2 = fm.enumerator(at: URL(fileURLWithPath: "/private" + base + "/real"), includingPropertiesForKeys: nil)!
while let u = e2.nextObject() as? URL { print("enum /private root:", u.path) }
// realpath case correction
let caseBase = base + "/Music/Rock"
try! fm.createDirectory(atPath: caseBase, withIntermediateDirectories: true)
var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
if realpath(base + "/music/rock", &buf) != nil { print("realpath(music/rock) =", String(cString: buf)) }
let fd = open(base + "/music/rock", O_RDONLY)
if fd >= 0 { var b2 = [CChar](repeating: 0, count: Int(MAXPATHLEN)); _ = fcntl(fd, F_GETPATH, &b2); print("F_GETPATH =", String(cString: b2)); close(fd) }
print("canonicalPath:", (try? URL(fileURLWithPath: base + "/music/rock").resourceValues(forKeys: [.canonicalPathKey]).canonicalPath) ?? "nil")
// symlinked root enumeration
let enumLink = fm.enumerator(at: URL(fileURLWithPath: base + "/link"), includingPropertiesForKeys: nil)!
var n = 0; while enumLink.nextObject() != nil { n += 1 }
print("enumerator(at: symlink-to-dir) yields", n, "entries; target has", (try? fm.contentsOfDirectory(atPath: base + "/real/sub").count) ?? -1)
fm.createFile(atPath: base + "/real/sub/s.flac", contents: Data())
let enumLink2 = fm.enumerator(at: URL(fileURLWithPath: base + "/link"), includingPropertiesForKeys: nil)!
while let u = enumLink2.nextObject() as? URL { print("enum via symlink root:", u.path) }
try? fm.removeItem(atPath: base)
