// ruleid: app-no-avaudiofile-position
session.audioFile.framePosition = max(0, min(startFrame, totalFrames))
// ruleid: app-no-avaudiofile-position
let atEnd = session.audioFile.framePosition >= session.audioFile.length
// ruleid: app-no-avaudiofile-position
let frames = file.length - file.framePosition
// ok: app-no-avaudiofile-position
// `AVAudioFile.framePosition` raises an uncaught NSException on a file its decoder refuses.
// ok: app-no-avaudiofile-position
/// The place is counted, never asked of the file (framePosition).
// ok: app-no-avaudiofile-position
try session.reader.seek(to: startFrame)
// ok: app-no-avaudiofile-position
player.scheduleSegment(file, startingFrame: frame, frameCount: count, at: nil)
