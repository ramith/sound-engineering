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
| cover | 64×64 blue PNG (embedded) |

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

The tests assert **tag values + cover presence/dedup/thumbnail**, never exact container
bytes, so a re-encode with a different ffmpeg version stays green.
