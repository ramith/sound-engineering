// S10.8 G break-it - queue edits and scrubs while PAUSED (see main.swift for the harness).

import Foundation

/// G-PAUSE-1: remove the PAUSED current song from the queue, then press Play.
@MainActor
func removePausedCurrent() async {
    let (model, engine) = makeVM(tracks: 3)
    await playAndSettle(model, at: 1, duration: 321)
    await pause(model, engine, at: 90)
    model.removeTrack(at: 1) // the context menu Remove from Queue on the paused current row
    let durationShown = model.duration
    model.play()
    await settle()
    let started = name(engine.starts.last?.url)
    report(engine.seeks.isEmpty, "G-PAUSE-1",
           "after removing the paused song, Play starts the song that took its place from the top",
           expected: "start track2.flac at 0:00, footer duration = track 2 (200 s)",
           actual: "started \(started), then seeked to \(engine.seeks) s (the paused offset of the removed song), "
               + "and the footer kept duration \(secs(durationShown)) s (the removed song)")
}

/// G-PAUSE-2: remove a song ABOVE the paused current song, then press Play.
@MainActor
func removeAbovePausedCurrent() async {
    let (model, engine) = makeVM(tracks: 3)
    await playAndSettle(model, at: 2)
    await pause(model, engine, at: 90)
    model.removeTrack(at: 0)
    model.tickTransport()
    let shownAfterRemove = model.playbackPosition
    model.play()
    await settle()
    report(engine.seeks.last == 90, "G-PAUSE-2",
           "removing an earlier queue row keeps the place of the paused song",
           expected: "Play resumes track2 at 90 s",
           actual: "the resume point was dropped (the scrubber reads \(secs(shownAfterRemove)) s after the next "
               + "tick), and Play restarted track2 from 0 (engine seeks: \(engine.seeks))")
}

/// G-PAUSE-3: drag a row from above the paused current song to below it, then press Play.
@MainActor
func reorderAcrossPausedCurrent() async {
    let (model, engine) = makeVM(tracks: 3)
    await playAndSettle(model, at: 2)
    await pause(model, engine, at: 90)
    model.movePlaylistItems(from: IndexSet(integer: 0), to: 3)
    model.play()
    await settle()
    report(engine.seeks.last == 90, "G-PAUSE-3",
           "reordering the queue keeps the place of the paused song",
           expected: "Play resumes track2 at 90 s",
           actual: "Play restarted track2 from 0 (engine seeks: \(engine.seeks))")
}

/// G-SEEK-1: drag the footer scrubber while PAUSED, then press Play.
@MainActor
func scrubWhilePaused() async {
    let (model, engine) = makeVM(tracks: 3)
    await playAndSettle(model, at: 0)
    await pause(model, engine, at: 90)
    model.seek(to: 30)
    await settle()
    let shownAfterSeek = model.playbackPosition
    model.play()
    await settle()
    report(engine.seeks.last == 30, "G-SEEK-1",
           "a scrub while paused is where Play resumes",
           expected: "resume at 30 s",
           actual: "the footer showed \(secs(shownAfterSeek)) s, then Play resumed at \(engine.seeks.last ?? -1) s "
               + "(the pre-scrub pause point), engine seeks in order: \(engine.seeks)")
}

/// G-SEEK-2: the queue ended, then the user clicks the scrubber.
@MainActor
func scrubAfterQueueEnded() async {
    let (model, engine) = makeVM(tracks: 2)
    await playAndSettle(model, at: 1)
    engine.ended = true
    model.tickTransport() // end of queue: stopped at 0, the last song still loaded
    let seeksBefore = engine.seeks.count
    model.seek(to: 60)
    await settle()
    model.tickTransport()
    report(engine.seeks.count == seeksBefore, "G-SEEK-2",
           "a scrub after the queue ended does not drive the still-running engine behind a stopped UI",
           expected: "no engine seek while stopped (or start playing there and show it)",
           actual: "engine.seek(60) sent while isPlaying=\(model.isPlaying), and the next tick puts the scrubber "
               + "back to \(secs(model.playbackPosition)) s (duration still \(secs(model.duration)) s: the scrubber "
               + "stays live)")
}
