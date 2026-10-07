#!/usr/bin/env python3
"""
Generate the stress library (S10.8 C1): about 10,000 tiny, real, tagged audio files for the isolated
debug test library (`make run-test-library`). It is written OUTSIDE the repo and only ever into a
folder this script made itself.

Usage:
    python3 scripts/generate-stress-library.py [--output DIR] [--bulk N]
    (default DIR: ~/Music/AdaptiveSound Stress Library; default N: 9,800 bulk tracks)

What is in it:
    Artists/          the bulk: hundreds of artists and albums in FLAC, MP3 and M4A, two in three with
                      embedded art, some multi-disc, some with and some without an album-artist tag
    Names/            very long, CJK, right-to-left (Arabic, Hebrew), emoji and Unicode-normalization names
    Compilations/     mixed-artist albums with and without the compilation flag (FLAC, MP3, M4A) and with
                      no album-artist tag — the Sprint C2 cases — plus the tagged "Various Artists" control
    Same Title/       same-title albums in different folders (same and different artists, same year)
    Surround/         5.1 (6-channel) and 7.1 (8-channel) channel checks, mono and 96 kHz / 24-bit files
    Edge/             untagged and partly tagged files, a one-hour track, a 3000 px cover, mixed art

How it stays fast: ffmpeg encodes ONE template per shape (format, channels, length); FLAC and MP3 copies
are retagged in-process (Vorbis comments + PICTURE; ID3v2.4 + APIC); only M4A goes back through ffmpeg,
as a parallel stream copy. Idempotent: a hidden manifest (the library scanner skips hidden files) records
each file's spec hash, so a re-run rewrites only what changed and removes only files it wrote.
"""

import argparse
import hashlib
import json
import os
import random
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import unicodedata
import zlib
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path

VERSION = 1
DEFAULT_OUTPUT = Path.home() / "Music" / "AdaptiveSound Stress Library"
DEFAULT_BULK = 9_800  # plus ~200 special cases ≈ 10,000 tracks
MANIFEST = ".adaptivesound-stress-library.json"
SEED = 20261007

# --- Templates ------------------------------------------------------------------------------------
# One ffmpeg encode per shape. Bulk FLAC is silence (a few KB); MP3 and M4A carry a quiet tone, so a
# founder playing a bulk song hears it is playing. Surround files carry a different note per channel.

QUIET = "volume=-18dB"
# Per-channel notes for the channel checks (front L/R, centre, LFE, side/back pairs): easy to tell apart.
NOTES = [261.63, 329.63, 392.00, 55.00, 440.00, 523.25, 659.25, 783.99]
LAYOUTS = {6: ("5.1", ["Front Left", "Front Right", "Center", "LFE", "Surround Left", "Surround Right"]),
           8: ("7.1", ["Front Left", "Front Right", "Center", "LFE", "Back Left", "Back Right",
                       "Side Left", "Side Right"])}
SILENCE_LENGTHS = [2, 3, 4, 6]  # bulk FLAC lengths, cycled so the Time column varies
LONG_TRACK_SECONDS = 3723  # 1:02:03 — an hour-long row


def _sine(freq, seconds, rate):
    return ["-f", "lavfi", "-i", f"sine=frequency={freq}:duration={seconds}:sample_rate={rate}"]


def _multichannel(channels, seconds=3, only=None):
    """Every channel its own note (or only channel `only`) in the 5.1 / 7.1 layout, from ONE source:
    joining several sources frames them differently run to run, which would defeat the manifest."""
    layout, _ = LAYOUTS[channels]
    exprs = "|".join(f"0.125*sin(2*PI*{NOTES[i]}*t)" if only in (None, i) else "0" for i in range(channels))
    source = f"aevalsrc=exprs={exprs}:channel_layout={layout}:sample_rate=48000:duration={seconds}"
    return ["-f", "lavfi", "-i", source]


def template_recipes():
    """Template key → (extension, ffmpeg input+filter+codec arguments)."""
    recipes = {}
    for seconds in SILENCE_LENGTHS:
        recipes[f"flac-silence-{seconds}s"] = (
            "flac", ["-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo", "-t", str(seconds), "-c:a", "flac"])
    recipes["flac-silence-long"] = (
        "flac", ["-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo", "-t", str(LONG_TRACK_SECONDS), "-c:a", "flac"])
    for seconds in (3, 5):
        recipes[f"mp3-tone-{seconds}s"] = ("mp3", _sine(440, seconds, 44100) + [
            "-af", f"aformat=channel_layouts=stereo,{QUIET}", "-c:a", "libmp3lame", "-b:a", "32k",
            "-id3v2_version", "0", "-write_xing", "1"])
    recipes["m4a-tone-3s"] = ("m4a", _sine(440, 3, 44100) + [
        "-af", f"aformat=channel_layouts=stereo,{QUIET}", "-c:a", "aac", "-b:a", "32k"])
    recipes["flac-tone-mono"] = ("flac", _sine(440, 3, 44100) + ["-af", QUIET, "-c:a", "flac"])
    recipes["flac-tone-hires"] = ("flac", _sine(1000, 3, 96000) + [
        "-af", f"aformat=channel_layouts=stereo,{QUIET}", "-c:a", "flac",
        "-sample_fmt", "s32", "-bits_per_raw_sample", "24"])
    for channels in LAYOUTS:
        flac = ["-c:a", "flac", "-sample_fmt", "s16"]
        recipes[f"flac-{channels}ch-all"] = ("flac", _multichannel(channels) + flac)
        for index in range(channels):
            recipes[f"flac-{channels}ch-{index}"] = ("flac", _multichannel(channels, only=index) + flac)
        recipes[f"m4a-{channels}ch-all"] = ("m4a", _multichannel(channels) + ["-c:a", "aac", "-b:a", "192k"])
    return recipes


@dataclass
class Template:
    path: Path
    data: bytes
    digest: str


def encode_templates(workdir):
    templates = {}
    for key, (ext, args) in template_recipes().items():
        path = workdir / f"{key}.{ext}"
        run_ffmpeg(args + ["-map_metadata", "-1", "-fflags", "+bitexact", str(path)])
        data = path.read_bytes()
        templates[key] = Template(path, data, hashlib.sha256(data).hexdigest())
    return templates


def run_ffmpeg(args):
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-y"] + args, check=True)


# --- Cover art (pure-Python PNG) ------------------------------------------------------------------

@dataclass(frozen=True)
class Art:
    seed: int
    size: int = 600

    def colors(self):
        rng = random.Random(self.seed)
        return [tuple(rng.randrange(256) for _ in range(3)) for _ in range(2)], rng.random() < 0.5

    def png(self):
        """A two-colour gradient, horizontal or vertical: distinct per album, a few KB compressed."""
        (start, end), vertical = self.colors()
        size = self.size

        def mix(t):
            return bytes(round(a + (b - a) * t) for a, b in zip(start, end))

        if vertical:  # each row one colour: filter Sub turns the rest of the row into zeros
            rows = b"".join(b"\x01" + mix(y / (size - 1)) + bytes(3 * (size - 1)) for y in range(size))
        else:  # one gradient row, then filter Up (zeros) for every row below it
            first = b"\x00" + b"".join(mix(x / (size - 1)) for x in range(size))
            rows = first + (b"\x02" + bytes(3 * size)) * (size - 1)

        def chunk(kind, body):
            return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

        header = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
        return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(rows, 6)) + \
            chunk(b"IEND", b"")


# --- Tag writers ----------------------------------------------------------------------------------
# Canonical tags: title, artist, album, album_artist, date, track, track_total, disc, disc_total,
# genre, compilation. Each writer maps them to its container's own spelling.

VORBIS = {"title": "TITLE", "artist": "ARTIST", "album": "ALBUM", "album_artist": "ALBUMARTIST", "date": "DATE",
          "track": "TRACKNUMBER", "track_total": "TRACKTOTAL", "disc": "DISCNUMBER", "disc_total": "DISCTOTAL",
          "genre": "GENRE", "compilation": "COMPILATION"}
ID3 = {"title": "TIT2", "artist": "TPE1", "album": "TALB", "album_artist": "TPE2", "date": "TDRC",
       "genre": "TCON", "compilation": "TCMP"}
MP4 = {"title": "title", "artist": "artist", "album": "album", "album_artist": "album_artist", "date": "date",
       "genre": "genre", "compilation": "compilation"}


def numbered(tags, key):
    """A track or disc number as ID3 and MP4 write it: "3/12", or "3" without a total."""
    if key not in tags:
        return None
    total = tags.get(f"{key}_total")
    return f"{tags[key]}/{total}" if total else str(tags[key])


def flac_with_tags(template, tags, art_png):
    data = template.data
    assert data[:4] == b"fLaC", "not a FLAC template"
    position, streaminfo = 4, None
    while True:  # keep STREAMINFO and the audio frames; drop ffmpeg's padding, seek table and comments
        header = data[position]
        length = int.from_bytes(data[position + 1:position + 4], "big")
        if header & 0x7F == 0:
            streaminfo = data[position + 4:position + 4 + length]
        position += 4 + length
        if header & 0x80:
            break
    blocks = [(0, streaminfo)]
    if tags:
        vendor = b"AdaptiveSound stress library"
        comments = [f"{VORBIS[key]}={value}".encode() for key, value in tags.items()]
        body = struct.pack("<I", len(vendor)) + vendor + struct.pack("<I", len(comments))
        blocks.append((4, body + b"".join(struct.pack("<I", len(c)) + c for c in comments)))
    if art_png:
        mime, size = b"image/png", struct.unpack(">I", art_png[16:20])[0]
        blocks.append((6, struct.pack(">II", 3, len(mime)) + mime + struct.pack(">IIIIII", 0, size, size, 24, 0,
                                                                               len(art_png)) + art_png))
    out = bytearray(b"fLaC")
    for index, (kind, body) in enumerate(blocks):
        out += bytes([kind | (0x80 if index == len(blocks) - 1 else 0)]) + len(body).to_bytes(3, "big") + body
    return bytes(out + data[position:])


def _synchsafe(value):
    return bytes([(value >> 21) & 0x7F, (value >> 14) & 0x7F, (value >> 7) & 0x7F, value & 0x7F])


def mp3_with_tags(template, tags, art_png):
    frames = []
    texts = {ID3[key]: value for key, value in tags.items() if key in ID3}
    for key, frame in (("track", "TRCK"), ("disc", "TPOS")):
        if numbered(tags, key):
            texts[frame] = numbered(tags, key)
    for frame, value in texts.items():  # ID3v2.4, UTF-8 text (encoding 3)
        body = b"\x03" + str(value).encode()
        frames.append(frame.encode() + _synchsafe(len(body)) + b"\x00\x00" + body)
    if art_png:  # front cover (type 3), empty description
        body = b"\x03image/png\x00\x03\x00" + art_png
        frames.append(b"APIC" + _synchsafe(len(body)) + b"\x00\x00" + body)
    if not frames:
        return template.data
    payload = b"".join(frames)
    return b"ID3\x04\x00\x00" + _synchsafe(len(payload)) + payload + template.data


def m4a_arguments(template, tags, cover_path):
    args = ["-i", str(template.path)]
    if cover_path:
        args += ["-i", str(cover_path)]
    args += ["-map", "0:a", "-c:a", "copy"]
    if cover_path:
        args += ["-map", "1:v", "-c:v", "copy", "-disposition:v:0", "attached_pic"]
    args += ["-map_metadata", "-1", "-fflags", "+bitexact"]
    for key, value in tags.items():
        if key in MP4:
            args += ["-metadata", f"{MP4[key]}={value}"]
    for key in ("track", "disc"):
        if numbered(tags, key):
            args += ["-metadata", f"{key}={numbered(tags, key)}"]
    return args


# --- The plan -------------------------------------------------------------------------------------

@dataclass
class Track:
    path: str  # relative to the library root
    template: str
    tags: dict = field(default_factory=dict)
    art: Art | None = None

    @property
    def extension(self):
        return Path(self.path).suffix[1:]


class Planner:
    """Builds every file's path and tags; paths are unique the way APFS sees them (case- and
    normalization-insensitive), and every component fits in 255 bytes."""

    def __init__(self):
        self.tracks = []
        self._taken = set()

    @staticmethod
    def component(name, limit=180):
        cleaned = "".join("-" if ch in "/:" else ch for ch in name if unicodedata.category(ch) != "Cc")
        cleaned = cleaned.strip().lstrip(".").rstrip(". ") or "_"
        encoded = cleaned.encode()
        if len(encoded) <= limit:
            return cleaned
        return encoded[:limit].decode(errors="ignore").rstrip() or "_"

    def add(self, folder, file_stem, template, tags=None, art=None):
        extension = template.split("-")[0]  # template keys start with their format
        parts = [self.component(part) for part in folder]
        stem = self.component(file_stem, limit=200)
        candidate, counter = "/".join(parts + [f"{stem}.{extension}"]), 2
        while unicodedata.normalize("NFD", candidate).casefold() in self._taken:
            candidate, counter = "/".join(parts + [f"{stem} ({counter}).{extension}"]), counter + 1
        self._taken.add(unicodedata.normalize("NFD", candidate).casefold())
        self.tracks.append(Track(candidate, template, {k: v for k, v in (tags or {}).items() if v is not None}, art))

    def album(self, folder, album, artists, template, *, album_artist=None, year=None, genre=None, art=None,
              titles=None, compilation=False, discs=1):
        """One album: `artists` is one name (shared) or one per track; `template` a key, or a key per
        track index."""
        count = len(titles) if titles else (len(artists) if isinstance(artists, list) else 10)
        titles = titles or [f"Track {n}" for n in range(1, count + 1)]
        per_disc = -(-count // discs)
        for index, title in enumerate(titles):
            disc, number = index // per_disc + 1, index % per_disc + 1
            artist = artists[index % len(artists)] if isinstance(artists, list) else artists
            tags = {"title": title, "artist": artist, "album": album, "album_artist": album_artist,
                    "date": year, "track": number, "track_total": min(per_disc, count - (disc - 1) * per_disc),
                    "genre": genre, "compilation": 1 if compilation else None}
            if discs > 1:
                tags |= {"disc": disc, "disc_total": discs}
            stem = f"{disc}-{number:02d} {title}" if discs > 1 else f"{number:02d} {title}"
            self.add(folder, stem, template(index) if callable(template) else template, tags, art)


FIRST = ["Mara", "Oskar", "Lena", "Teo", "Ines", "Kai", "Noor", "Ravi", "Elsa", "Milo", "Yara", "Jonas", "Ada",
         "Felix", "Sana", "Hugo", "Iris", "Leo", "Nina", "Omar", "Tove", "Emil", "Lucía", "Zoë", "Björn", "Aoife",
         "Søren", "Chiara", "Mateo", "Priya"]
LAST = ["Lind", "Vale", "Marsh", "Okafor", "Brandt", "Castell", "Duarte", "Ferro", "Halvorsen", "Ibarra", "Jansen",
        "Kowalski", "Laurent", "Moreau", "Novak", "Ortega", "Petrov", "Quinn", "Rossi", "Sato", "Sørensen", "Núñez",
        "Dvořák", "Ångström", "Müller", "Gonçalves", "Çelik", "Þórsson", "Ruiz-Peña", "O'Brien"]
ADJECTIVES = ["Silver", "Hollow", "Neon", "Paper", "Velvet", "Copper", "Midnight", "Northern", "Glass", "Electric",
              "Quiet", "Golden", "Static", "Wild", "Lunar", "Crimson", "Faded", "Little", "Broken", "Distant",
              "Endless", "Secret", "Burning", "Frozen", "Hidden", "Last", "Open", "Slow", "Strange", "Bright"]
NOUNS = ["Harbor", "Lights", "Engines", "Kites", "Foxes", "Rivers", "Signals", "Gardens", "Machines", "Pilots",
         "Tides", "Satellites", "Owls", "Parade", "Echoes", "Hearts", "Ghosts", "Trains", "Mirrors", "Summers",
         "Cities", "Wolves", "Letters", "Islands", "Bridges", "Shadows", "Waves", "Stars", "Roads", "Dreams"]
GENRES = ["Rock", "Pop", "Jazz", "Classical", "Electronic", "Hip-Hop", "Folk", "Ambient", "Soul", "Funk", "Metal",
          "Blues", "Reggae", "Country", "R&B", "Indie", "Punk", "House", "Techno", "Soundtrack", "World", "Latin",
          "K-Pop", "J-Pop", "Bossa Nova"]


def artist_name(rng):
    roll = rng.random()
    if roll < 0.5:
        return f"{rng.choice(FIRST)} {rng.choice(LAST)}"
    if roll < 0.9:
        return f"The {rng.choice(ADJECTIVES)} {rng.choice(NOUNS)}"
    return f"{rng.choice(ADJECTIVES)} {rng.choice(NOUNS)}"


def album_title(rng):
    adjective, noun, other = rng.choice(ADJECTIVES), rng.choice(NOUNS), rng.choice(NOUNS)
    return rng.choice([f"{adjective} {noun}", f"{noun} of {other}", f"The {noun}", noun, f"{noun} & {other}",
                       f"Live at the {adjective} {noun}", f"{adjective} {noun} (Deluxe Edition)",
                       f"{noun}, Vol. {rng.randint(2, 4)}",
                       f"{adjective} {noun} (Remastered {rng.randint(2001, 2024)})"])


def track_title(rng, artist):
    adjective, noun = rng.choice(ADJECTIVES), rng.choice(NOUNS)
    title = rng.choice([f"{adjective} {noun}", f"{noun}", f"The {adjective} {noun}", f"{noun} in the {adjective}",
                        f"{adjective} {noun}, Part {rng.choice(['I', 'II', 'III'])}", f"{noun} (Interlude)",
                        f"{adjective} {noun} - Radio Edit"])
    if rng.random() < 0.05:
        title += f" (feat. {artist_name(rng)})"
    return title


BULK_TEMPLATES = {"flac": lambda i: f"flac-silence-{SILENCE_LENGTHS[i % len(SILENCE_LENGTHS)]}s",
                  "mp3": lambda i: f"mp3-tone-{3 if i % 3 else 5}s",
                  "m4a": lambda i: "m4a-tone-3s"}


def plan_bulk(planner, rng, target):
    """Artists/<artist>/<album>/: runs first, so every planned track so far is a bulk one."""
    album_seed = 0
    while len(planner.tracks) < target:
        artist = artist_name(rng)
        for _ in range(rng.randint(1, 4)):
            album_seed += 1
            album = album_title(rng)
            fmt = rng.choices(["flac", "mp3", "m4a"], weights=[65, 30, 5])[0]
            count = rng.randint(6, 18)
            genre = rng.choice(GENRES) if rng.random() < 0.9 else f"{rng.choice(GENRES)}; {rng.choice(GENRES)}"
            planner.album(["Artists", artist, album], album, artist, BULK_TEMPLATES[fmt],
                          album_artist=artist if rng.random() < 0.6 else None, year=rng.randint(1962, 2025),
                          genre=genre, art=Art(album_seed) if rng.random() < 0.65 else None,
                          titles=[track_title(rng, artist) for _ in range(count)],
                          discs=2 if rng.random() < 0.05 and count >= 10 else 1)


def plan_names(planner):
    long_artist = ("The Extraordinarily Long-Named Philharmonic Orchestra and Chorus of the Northern Coastal "
                   "Provinces featuring Many Distinguished Guest Soloists")
    long_album = ("Complete Symphonic Works, Concertos, Overtures, Fragments, Sketches, Alternate Takes and "
                  "Previously Unreleased Rehearsal Recordings from the Legendary 1971–1979 Winter Seasons "
                  "(Fully Restored 50th Anniversary Super Deluxe Collector's Box Set Edition)")
    planner.album(["Names", "Very Long"], long_album, long_artist, "flac-silence-3s", album_artist=long_artist,
                  year=1979, genre="Classical", art=Art(9001), titles=[
                      "Symphony No. 9 in D minor, Op. 125 'Choral': IV. Presto — Allegro assai — Allegro assai "
                      "vivace (alla marcia) — Andante maestoso — Adagio ma non troppo, ma divoto — Allegro "
                      "energico, sempre ben marcato — Allegro ma non tanto — Prestissimo",
                      "Pneumonoultramicroscopicsilicovolcanoconiosis" * 3,
                      "A Song (feat. Somebody) [Remastered 2011] {Live at the Hall} (Bonus Track) (Single Version) "
                      "(Extended Mix) (Instrumental) — Take 3",
                      "Short", "  Leading and trailing spaces  ", "Ellipsis at the end…", "Tab\tinside", "x"])
    planner.album(["Names", "CJK", "Japanese"], "東京の夜明け", "山田花子", "flac-silence-3s", album_artist="山田花子",
                  year=2019, genre="J-Pop", art=Art(9002),
                  titles=["夜明けのうた", "青い月", "ＴＯＫＹＯ ＮＩＧＨＴ（全角）", "桜の木の下で", "ありがとう、さようなら"])
    planner.album(["Names", "CJK", "Chinese"], "春风十里的回声", "林小雨", "mp3-tone-3s", album_artist="林小雨",
                  year=2016, genre="Pop", art=None, titles=["夜空中的星", "回声", "长安的雪", "你好，世界"])
    planner.album(["Names", "CJK", "Korean"], "푸른 바다의 노래", "김하늘", "m4a-tone-3s", album_artist="김하늘",
                  year=2021, genre="K-Pop", art=Art(9003), titles=["바다", "별빛 아래서", "안녕 (Hello)", "Seoul 2021 서울"])
    planner.album(["Names", "CJK", "Mixed"], "Tokyo 夜景 Remixes", ["DJ Kenji 健二", "林小雨", "김하늘"],
                  "flac-silence-2s", year=2022, genre="Electronic", art=Art(9004),
                  titles=["Shibuya 渋谷 Crossing", "上海 Shanghai Lights", "부산 Busan Waves"])
    planner.album(["Names", "RTL", "Arabic"], "أغاني الصحراء", "فرقة النجوم", "flac-silence-3s",
                  album_artist="فرقة النجوم", year=2015, genre="World", art=Art(9005),
                  titles=["ليلة القمر", "رمال", "يا حبيبي", "الطريق إلى القاهرة"])
    planner.album(["Names", "RTL", "Hebrew"], "שירי הים", "להקת האור", "mp3-tone-3s", album_artist="להקת האור",
                  year=2018, genre="Folk", art=None, titles=["גלים", "לילה טוב", "ירושלים של זהב", "שיר 2"])
    planner.album(["Names", "RTL", "Mixed direction"], "Live in القاهرة 2019", "Omar Haddad عمر حداد",
                  "flac-silence-3s", album_artist="Omar Haddad عمر حداد", year=2019, genre="World", art=Art(9006),
                  titles=["Intro مقدمة", "Track 2 (שיר שני)", "123 أرقام 456", "(Parentheses) [Brackets] أقواس"])
    planner.album(["Names", "Emoji"], "🌊🌊🌊", "DJ 🦄 Sparkle", "m4a-tone-3s", album_artist="DJ 🦄 Sparkle",
                  year=2023, genre="Electronic", art=Art(9007),
                  titles=["🔥", "👩‍🚀 Launch Sequence", "🇯🇵 → 🇧🇷 Flight", "👋🏽 Hello", "1️⃣ Keycap",
                          "❤️‍🔥 Heart on Fire", "🎧💿📼 Formats"])
    planner.album(["Names", "Emoji", "Mixed"], "Late Night 🌙 Drive", "Neon 🚗 Club", "mp3-tone-3s",
                  year=2020, genre="Synthwave", art=None, titles=["Exit 🛣️ 42", "☕️ at 3am", "Sunrise 🌅"])
    # Same visible names, different Unicode: an NFC and an NFD spelling of one artist, in two folders.
    for form, seed in (("NFC", 9008), ("NFD", 9009)):
        artist = unicodedata.normalize(form, "Zoë Ångström")
        planner.album(["Names", f"Normalization {form}"], unicodedata.normalize(form, f"Café Sessions ({form})"),
                      artist, "flac-silence-2s", album_artist=artist, year=2017, genre="Jazz", art=Art(seed),
                      titles=[unicodedata.normalize(form, t) for t in ("Crème Brûlée", "Naïve", "Façade")])


def plan_compilations(planner):
    guests = ["Mara Lind", "Oskar Vale", "The Silver Harbor", "Yara Okafor", "Neon Tides", "Kai Sato",
              "Lucía Núñez", "The Paper Kites Collective", "Teo Ferro", "Søren Dvořák", "Ines Duarte", "Hollow Owls"]
    base = ["Compilations"]
    # The C2 case: mixed artists, compilation flag, NO album-artist tag — in all three tag dialects.
    planner.album(base + ["Summer Hits (flagged, FLAC)"], "Summer Hits Collection", guests, "flac-silence-3s",
                  compilation=True, year=2012, genre="Pop", art=Art(9101))
    planner.album(base + ["Late Night Sessions (flagged, MP3)"], "Late Night Sessions", guests[:10],
                  "mp3-tone-3s", compilation=True, year=2014, genre="Jazz", art=Art(9102))
    planner.album(base + ["Road Trip Mix (flagged, M4A)"], "Road Trip Mix", guests[2:12], "m4a-tone-3s",
                  compilation=True, year=2016, genre="Rock", art=Art(9103))
    # Mixed artists, NO flag, NO album artist: decision 12 still groups it under "Various Artists".
    planner.album(base + ["Indie Discoveries (unflagged)"], "Indie Discoveries", guests, "flac-silence-2s",
                  year=2018, genre="Indie", art=None)
    planner.album(base + ["Indie Discoveries (unflagged, MP3)"], "Coffee House Picks", guests[:8], "mp3-tone-3s",
                  year=2019, genre="Folk", art=Art(9104))
    # The control: the conventional "Various Artists" album-artist tag, no flag.
    planner.album(base + ["Movie Themes (Various Artists tag)"], "Movie Themes", guests[:9], "flac-silence-3s",
                  album_artist="Various Artists", year=2010, genre="Soundtrack", art=Art(9105))
    # A DJ mix: flagged, mixed artists, but WITH an album artist.
    planner.album(base + ["Club Mix (flagged, DJ album artist)"], "Kestrel Presents: Club Mix", guests[:8],
                  "flac-silence-4s", album_artist="DJ Kestrel", compilation=True, year=2021, genre="House",
                  art=Art(9106))
    # One primary artist with guests ("A" and "A feat. B"): shared artist or mixed? A C2 judgement call.
    planner.album(base + ["Duets (one artist, many guests)"], "Duets", ["Mara Lind"] + [
        f"Mara Lind feat. {guest}" for guest in guests[1:7]], "flac-silence-3s", year=2020, genre="Pop",
        art=Art(9107))


def plan_same_titles(planner):
    base = ["Same Title"]
    # Same title + same year, different folders, different artists, no album-artist tag (ALB-05).
    planner.album(base + ["Collection One", "Greatest Hits"], "Greatest Hits", "Harbor Lights", "flac-silence-3s",
                  year=2004, genre="Rock", art=Art(9201))
    planner.album(base + ["Collection Two", "Greatest Hits"], "Greatest Hits", "Copper Fields", "mp3-tone-3s",
                  year=2004, genre="Country", art=Art(9202))
    # Same title + year + artist, different folders, no album-artist tag: two different concerts.
    planner.album(base + ["Northbound 1999 Spring", "Live"], "Live", "Northbound", "flac-silence-2s", year=1999,
                  genre="Rock", art=Art(9203), titles=["Opening", "Northern Song", "Encore"])
    planner.album(base + ["Northbound 1999 Autumn", "Live"], "Live", "Northbound", "flac-silence-2s", year=1999,
                  genre="Rock", art=None, titles=["Intro", "Southern Song", "Goodnight"])
    # Same title with album-artist tags: different artists, so different albums under the S8 identity.
    planner.album(base + ["Ana Rui", "Untitled"], "Untitled", "Ana Rui", "flac-silence-3s", album_artist="Ana Rui",
                  year=2011, genre="Ambient", art=Art(9204), titles=["One", "Two", "Three"])
    planner.album(base + ["Ben Ode", "Untitled"], "Untitled", "Ben Ode", "m4a-tone-3s", album_artist="Ben Ode",
                  year=2013, genre="Ambient", art=Art(9205), titles=["One", "Two", "Three"])


def plan_surround(planner):
    for channels, (layout, names) in LAYOUTS.items():
        album = f"Channel Check {layout}"
        planner.add(["Surround", album], "00 All Channels", f"flac-{channels}ch-all",
                    {"title": f"All Channels ({layout})", "artist": "AdaptiveSound Test Tones", "album": album,
                     "album_artist": "AdaptiveSound Test Tones", "track": 1, "genre": "Test Tones", "date": 2026})
        for index, name in enumerate(names):
            planner.add(["Surround", album], f"{index + 1:02d} {name} only", f"flac-{channels}ch-{index}",
                        {"title": f"{name} only", "artist": "AdaptiveSound Test Tones", "album": album,
                         "album_artist": "AdaptiveSound Test Tones", "track": index + 2, "genre": "Test Tones",
                         "date": 2026})
        planner.add(["Surround", "Surround AAC"], f"{layout} All Channels", f"m4a-{channels}ch-all",
                    {"title": f"All Channels ({layout}, AAC)", "artist": "AdaptiveSound Test Tones",
                     "album": "Surround AAC", "album_artist": "AdaptiveSound Test Tones",
                     "track": 1 if channels == 6 else 2, "genre": "Test Tones", "date": 2026})
    for key, title in (("flac-tone-mono", "Mono (1 channel)"), ("flac-tone-hires", "96 kHz 24-bit stereo")):
        planner.add(["Surround", "Formats"], title, key,
                    {"title": title, "artist": "AdaptiveSound Test Tones", "album": "Formats",
                     "album_artist": "AdaptiveSound Test Tones", "genre": "Test Tones", "date": 2026})


def plan_edges(planner):
    for template in ("flac-silence-3s", "mp3-tone-3s", "m4a-tone-3s"):
        planner.add(["Edge", "Untagged"], f"untagged {template.split('-')[0]} file", template)
    planner.add(["Edge", "Partly tagged"], "title only", "flac-silence-2s", {"title": "Only a Title"})
    planner.add(["Edge", "Partly tagged"], "artist only", "mp3-tone-3s", {"artist": "Only an Artist"})
    planner.add(["Edge", "Partly tagged"], "album only", "flac-silence-2s", {"album": "Only an Album"})
    planner.add(["Edge", "Partly tagged"], "no track number", "flac-silence-2s",
                {"title": "No Track Number", "artist": "Mara Lind", "album": "Loose Ends"})
    planner.album(["Edge", "Multi-disc"], "The Double Album", "Velvet Signals", "flac-silence-2s",
                  album_artist="Velvet Signals", year=1997, genre="Rock", art=Art(9301), discs=2,
                  titles=[f"Side {'ABCD'[i // 4]} Song {i % 4 + 1}" for i in range(16)])
    planner.add(["Edge", "Long track"], "01 One Hour Two Minutes Three Seconds", "flac-silence-long",
                {"title": "One Hour, Two Minutes, Three Seconds", "artist": "Slow Drone Ensemble",
                 "album": "Patience", "album_artist": "Slow Drone Ensemble", "track": 1, "date": 2008,
                 "genre": "Ambient"}, Art(9302))
    planner.album(["Edge", "Huge cover"], "Billboard Size", "Wide Open Spaces", "flac-silence-2s",
                  album_artist="Wide Open Spaces", year=2024, genre="Ambient", art=Art(9303, size=3000),
                  titles=["Big", "Bigger", "Biggest"])
    # One album, three covers: tracks 1–3 cover A, 4–6 none, 7–8 cover B.
    covers = [Art(9304)] * 3 + [None] * 3 + [Art(9305)] * 2
    for index, art in enumerate(covers):
        planner.add(["Edge", "Mixed art"], f"{index + 1:02d} Song {index + 1}", "flac-silence-2s",
                    {"title": f"Song {index + 1}", "artist": "Patchwork", "album": "Mixed Art",
                     "album_artist": "Patchwork", "track": index + 1, "date": 2009, "genre": "Indie"}, art)
    # Case variants of one artist, as real taggers produce them.
    for artist, album, seed in (("Neon Harbor", "Lights", 9306), ("neon harbor", "Tides", 9307),
                                ("NEON HARBOR", "Signals", 9308)):
        planner.album(["Edge", "Case variants", f"{artist} - {album}"], album, artist, "mp3-tone-3s",
                      album_artist=artist, year=2015, genre="Indie", art=Art(seed), titles=["First", "Second"])


def build_plan(bulk):
    planner = Planner()
    plan_bulk(planner, random.Random(SEED), bulk)
    plan_names(planner)
    plan_compilations(planner)
    plan_same_titles(planner)
    plan_surround(planner)
    plan_edges(planner)
    return planner.tracks


# --- Writing --------------------------------------------------------------------------------------

def spec_hash(track, template):
    spec = [VERSION, track.template, template.digest, sorted(track.tags.items(), key=lambda kv: kv[0]),
            [track.art.seed, track.art.size] if track.art else None]
    return hashlib.sha256(json.dumps(spec, ensure_ascii=False, default=str).encode()).hexdigest()


def write_atomically(path, data):
    temporary = path.with_name(f".tmp-{path.name}")  # hidden: a running scan never picks it up
    temporary.write_bytes(data)
    os.replace(temporary, path)


def guard_output(root, repo_root):
    if root == repo_root or repo_root in root.parents:
        sys.exit(f"stress library: refusing to write inside the repo ({root}); pick a folder outside it")
    if root.exists() and any(root.iterdir()) and not (root / MANIFEST).exists():
        sys.exit(f"stress library: {root} is not empty and is not a stress library (no {MANIFEST}); "
                 "refusing to write into it")


def generate(root, bulk):
    started = time.monotonic()
    guard_output(root, Path(__file__).resolve().parents[1])
    if not shutil.which("ffmpeg"):
        sys.exit("stress library: ffmpeg not found (brew install ffmpeg)")
    root.mkdir(parents=True, exist_ok=True)
    manifest_path = root / MANIFEST
    previous = json.loads(manifest_path.read_text())["files"] if manifest_path.exists() else {}
    files, written, jobs = {}, 0, []
    with tempfile.TemporaryDirectory(prefix="stress-library-") as scratch:
        scratch = Path(scratch)
        templates = encode_templates(scratch)
        art_cache = {}

        def art_png(art):
            if art and art not in art_cache:
                art_cache[art] = art.png()
            return art_cache.get(art)

        for track in build_plan(bulk):
            template = templates[track.template]
            digest = spec_hash(track, template)
            path = root / track.path
            known = previous.get(track.path)
            if known and known["hash"] == digest and path.is_file() and path.stat().st_size == known["size"]:
                files[track.path] = known
                continue
            path.parent.mkdir(parents=True, exist_ok=True)
            png = art_png(track.art)
            if track.extension == "flac":
                write_atomically(path, flac_with_tags(template, track.tags, png))
            elif track.extension == "mp3":
                write_atomically(path, mp3_with_tags(template, track.tags, png))
            else:
                cover = None
                if png:
                    cover = scratch / f"cover-{track.art.seed}-{track.art.size}.png"
                    if not cover.exists():
                        cover.write_bytes(png)
                temporary = path.with_name(f".tmp-{path.name}")
                jobs.append((track.path, digest, path, temporary,
                             m4a_arguments(template, track.tags, cover) + ["-f", "ipod", str(temporary)]))
                continue
            files[track.path] = {"hash": digest, "size": path.stat().st_size}
            written += 1

        def remux(job):
            relative, digest, path, temporary, args = job
            run_ffmpeg(args)
            os.replace(temporary, path)
            return relative, {"hash": digest, "size": path.stat().st_size}

        with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as pool:
            for relative, entry in pool.map(remux, jobs):
                files[relative] = entry
                written += 1

    removed = 0
    for relative in previous.keys() - files.keys():  # only files this script wrote before
        stale = root / relative
        if stale.is_file():
            stale.unlink()
            removed += 1
    for directory, _, names in os.walk(root, topdown=False):  # an interrupted run's leftovers
        for name in names:
            if name.startswith(".tmp-"):
                (Path(directory) / name).unlink()
        if Path(directory) != root and not any(Path(directory).iterdir()):
            Path(directory).rmdir()
    manifest = json.dumps({"version": VERSION, "files": files}, ensure_ascii=False, indent=0).encode()
    if not manifest_path.exists() or manifest_path.read_bytes() != manifest:  # a no-op run touches nothing
        write_atomically(manifest_path, manifest)
    return len(files), written, removed, time.monotonic() - started


def disk_usage(root):
    total = 0
    for directory, _, names in os.walk(root):
        for name in names:
            total += os.lstat(os.path.join(directory, name)).st_blocks * 512
    return total


def main():
    parser = argparse.ArgumentParser(description="Generate the AdaptiveSound stress library (S10.8 C1).")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT, help=f"default: {DEFAULT_OUTPUT}")
    parser.add_argument("--bulk", type=int, default=DEFAULT_BULK, help="bulk tracks under Artists/ (default 9,800)")
    args = parser.parse_args()
    root = args.output.expanduser().resolve()
    total, written, removed, seconds = generate(root, args.bulk)
    print(f"stress library: {total:,} tracks ({written:,} written, {total - written:,} unchanged, {removed:,} "
          f"removed) in {seconds:.1f} s — {disk_usage(root) / 1_000_000:.0f} MB on disk at {root}")


if __name__ == "__main__":
    main()
