# Metadata-extraction test fixtures (S8.3)

Tiny, **self-made, public-domain** tagged audio files for the real-extraction gate
(`VerifyLibraryStore` cases Y/Z — `ChecksMetadataReal.swift`). They exercise both
extraction paths end to end (scan → metadata pass → store): the **AVFoundation** path
(`fixture.m4a`) and the **FFmpeg** path (`fixture.flac`).

Not copyrighted: a ~0.3 s self-generated sine tone + a 64×64 solid-blue cover, tagged via
the `ffmpeg` CLI. Each file is < 30 KB.

## Baked tags (asserted by the tests)

| tag | value |
|---|---|
| title | `Verify Title` |
| artist | `Verify Artist` |
| album | `Verify Album` |
| album_artist | `Verify Artist` |
| date / year | `2001` |
| track | `3/12` → trackNo 3 |
| disc | `1/2` → discNo 1 |
| genre | `TestGenre` |
| cover | 64×64 blue PNG (embedded verbatim via `-c:v copy`) |
| cover sha256 | `4c8ff0b8b24e8f75341bf3dae1e8370621da5eed3e2d756fbef54672a5fedcb2` |

The cover is copied VERBATIM into both containers, so the extracted bytes are byte-identical
across the m4a and flac AND stable across ffmpeg versions. `ChecksMetadataReal` pins that
sha256 (`knownCoverSHA256`) and asserts the written `artwork_key` equals it — a byte-exact
provenance check. If a regen changes the cover, `make regenerate-metadata-fixtures` prints the
new hash; update it there + in `knownCoverSHA256`.

`no-tags.m4a` is the same tone with **all** metadata stripped (`-map_metadata -1`) — the
tagless anti-loop shape (though the store-level anti-loop is proven synthetically in
`ChecksMetadataPass`).

## Authoritative — the gate NEVER runs `ffmpeg`

These checked-in files are the source of truth; `make gate` reads them directly (a builder
without `ffmpeg`, or a different FFmpeg build producing different container bytes, must not
break the gate). Regenerate ONLY when deliberately changing the fixtures:

```
make regenerate-metadata-fixtures
```

The tests assert **tag values + the cover's byte-exact sha256 + thumbnail**, never the exact
audio-container bytes — so an audio re-encode with a different ffmpeg version stays green,
while the verbatim-copied cover stays byte-stable (see the pinned hash above).
