import io
path = "Sources/LibraryScan/LibraryScanner.swift"
with io.open(path, "r", encoding="utf-8") as fh:
    text = fh.read()

old = """        if let enumerator {
            for case let fileURL as URL in enumerator {
                // S8.2b: Task.checkCancellation() goes here (per file, not per batch).
                guard let scanned = Self.makeScannedFile(fileURL: fileURL, root: root) else {
                    filesSkipped += 1
                    continue
                }
                filesSeen += 1
                batch.append(scanned)
                if batch.count >= Self.batchSize {
                    let ids = try await store.upsert(batch, folderID: folderID, generation: generation)
                    trackIDs.append(contentsOf: ids)
                    batch.removeAll(keepingCapacity: true)
                }
            }
        }"""

# `nextObject()` is used (not `for..in`) because `NSEnumerator.makeIterator` is
# unavailable in an async context (a hard error under the Swift 6 language mode);
# the manual next-loop is the async-safe walk.
new = """        if let enumerator {
            while let next = enumerator.nextObject() {
                // S8.2b: Task.checkCancellation() goes here (per file, not per batch).
                guard let fileURL = next as? URL else { continue }
                guard let scanned = Self.makeScannedFile(fileURL: fileURL, root: root) else {
                    filesSkipped += 1
                    continue
                }
                filesSeen += 1
                batch.append(scanned)
                if batch.count >= Self.batchSize {
                    let ids = try await store.upsert(batch, folderID: folderID, generation: generation)
                    trackIDs.append(contentsOf: ids)
                    batch.removeAll(keepingCapacity: true)
                }
            }
        }"""
assert old in text, "scanner loop anchor not found"
text = text.replace(old, new, 1)
with io.open(path, "w", encoding="utf-8") as fh:
    fh.write(text)
print("Scanner loop patched to async-safe nextObject() walk")
PY
