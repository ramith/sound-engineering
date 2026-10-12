// S10.8 G break-it - repeat toggled while a song plays (see main.swift for the harness).

import Foundation

/// G-RPT-1: Repeat One turned on while a song plays.
@MainActor
func repeatOneTurnedOn() async {
    let (model, engine) = makeVM(tracks: 3)
    await playAndSettle(model, at: 0)
    model.cycleRepeatMode() // off to all
    model.cycleRepeatMode() // all to one
    await settle()
    let armed = engine.armed.last ?? nil
    engine.transitions += 1 // the engine plays what is armed at the seam
    model.tickTransport()
    report(both(model.selectedTrackIndex == 0, armed == url(0)), "G-RPT-1",
           "Repeat One turned on mid-song repeats THIS song at its end",
           expected: "on-deck = track0, and after the seam the current track is 0",
           actual: "on-deck = \(name(armed)), and after the seam the current track is "
               + text(model.selectedTrackIndex))
}

/// G-RPT-2: Repeat All turned on while the LAST song plays.
@MainActor
func repeatAllTurnedOnOnLastSong() async {
    let (model, engine) = makeVM(tracks: 3)
    await playAndSettle(model, at: 2)
    model.cycleRepeatMode() // off to all
    await settle()
    engine.ended = true // the last song ends
    model.tickTransport()
    report(both(model.isPlaying, model.selectedTrackIndex == 0), "G-RPT-2",
           "Repeat All turned on during the last song wraps to the first at its end",
           expected: "playing track 0",
           actual: "isPlaying=\(model.isPlaying) current=\(text(model.selectedTrackIndex)) "
               + "pendingNextIndex=\(text(model.pendingNextIndex)) (the queue stopped)")
}

/// G-RPT-3: Repeat One turned OFF while a song plays (repeat-one had armed the same song).
@MainActor
func repeatOneTurnedOff() async {
    let (model, engine) = makeVM(tracks: 3)
    model.repeatMode = 2
    await playAndSettle(model, at: 0)
    model.cycleRepeatMode() // one to off
    await settle()
    engine.transitions += 1
    model.tickTransport()
    report(model.selectedTrackIndex == 1, "G-RPT-3",
           "Repeat turned off mid-song moves on to the next song at its end",
           expected: "current track 1 after the seam",
           actual: "current track \(text(model.selectedTrackIndex)) (the song repeats once more)")
}
