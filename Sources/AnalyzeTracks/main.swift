// AnalyzeTracks — the read-only analysis tool (R1.1-B, founder decision 4; the level-and-fold design,
// docs/design/level-and-fold/README.md, "The analysis tool").
//
// Lane 1's executable in W4 (§9, order step 7). It prints what the one analysis pass measures for the files
// named on its command line: loudness and true peak as decoded and on the fold, the LFE statistics. It writes
// nothing in AppDataLocation. Empty at the coordinator's commit 0, so the target exists before the lanes start.

import Foundation

FileHandle.standardError.write(Data("AnalyzeTracks: not built yet (R1.1-B W4, lane 1)\n".utf8))
exit(2)
