import Foundation
for p in CommandLine.arguments.dropFirst() {
  var u = URL(fileURLWithPath: p).resolvingSymlinksInPath()
  u.removeAllCachedResourceValues()
  let v = try? u.resourceValues(forKeys: [.volumeUUIDStringKey, .volumeIsRootFileSystemKey, .volumeNameKey, .isVolumeKey, .volumeIsInternalKey, .volumeIdentifierKey])
  print(p, "→ uuid=\(v?.volumeUUIDString ?? "nil") isRootFS=\(String(describing: v?.volumeIsRootFileSystem)) name=\(v?.volumeName ?? "-") internal=\(String(describing: v?.volumeIsInternal))")
}
