// S10.8 G break-it - transport presses while a start is still in flight (see main.swift).

import Foundation

/// G-RACE-1: Play/Pause pressed again before the first start lands (a slow Pure or device start).
@MainActor
func secondPressDuringStart() async {
    let (model, engine) = makeVM(tracks: 3)
    model.playTrack(at: 0)
    model.togglePlayPause() // the second press, while isPlaying is still false
    await settle()
    report(engine.starts.count == 1, "G-RACE-1",
           "a second Play/Pause press during start-up does not start the song again",
           expected: "1 engine start (the press pauses, or is ignored)",
           actual: "\(engine.starts.count) engine starts, isPlaying=\(model.isPlaying)")
}

/// G-RACE-2: Clear Queue while a start is still in flight.
@MainActor
func clearDuringStart() async {
    let (model, engine) = makeVM(tracks: 3)
    model.playTrack(at: 0)
    model.clearPlaylist()
    await settle()
    report(model.isPlaying == false, "G-RACE-2",
           "Clear Queue during start-up leaves the transport stopped",
           expected: "isPlaying=false with an empty queue",
           actual: "isPlaying=\(model.isPlaying), queue=\(model.queue.count), engine starts=\(engine.starts.count), "
               + "stops=\(engine.stops)")
}
