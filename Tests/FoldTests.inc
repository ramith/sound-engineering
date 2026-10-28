// FoldTests.inc
//
// The BS.775 fold: the matrix from roles, the per-track trim with the leveling gain, the backstop (§S2).
// #included into Tests/DSPKernelNullTest.cpp after TestSupport.h; its rows go in the kTests block
// marked "FoldTests.inc" there, so the two lanes never edit the same lines of the table.
//
// Empty at the coordinator's commit 0 of W4 (R1.1-B level-and-fold, docs/design/level-and-fold/README.md §9):
// lane 2 owns this file.
