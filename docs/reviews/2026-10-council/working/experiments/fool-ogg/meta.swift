import AVFoundation
let sem = DispatchSemaphore(value: 0)
Task {
  for p in CommandLine.arguments.dropFirst() {
    let a = AVURLAsset(url: URL(fileURLWithPath: p))
    do {
      let items = try await a.load(.metadata)
      var out: [String] = []
      for i in items { let k = i.identifier?.rawValue ?? "?"; let v = (try? await i.load(.stringValue)) ?? "-"; out.append("\(k)=\(v ?? "nil")") }
      let fmts = try await a.load(.availableMetadataFormats)
      print(p, "items:", items.count, "formats:", fmts.map{$0.rawValue}, out.prefix(6))
    } catch { print(p, "ERR", error) }
  }
  sem.signal()
}
sem.wait()
