"""Command-line interface for the legacy-remaster POC.

    legacy-remaster PATH                       # remaster PATH and play it (bare path => `play`)
    legacy-remaster play PATH [--keep OUT]      # remaster and play (afplay/ffplay)
    legacy-remaster remaster PATH [-o OUT]      # remaster to a WAV file
    legacy-remaster make-test OUTDIR            # synth modern+legacy fixtures
    legacy-remaster bakeoff PATH [--out DIR]    # bandwidth-extension method comparison
    legacy-remaster sim [--rtf R] [...]         # process-ahead buffer simulation

Accepts wav/flac/ogg/mp3 (libsndfile) and m4a/aac/mp4 (ffmpeg/afconvert). Output is WAV.
"""
from __future__ import annotations

import argparse
import logging
import os
import shutil
import subprocess
import sys
import tempfile
import time

import numpy as np

from . import analyze, audioio, bakeoff, sim, synth, verify
from .loudness import integrated_lufs
from .pipeline import RemasterConfig, remaster

log = logging.getLogger("legacy-remaster")

WORK_SR = 44100
SUBCOMMANDS = {"play", "remaster", "make-test", "bakeoff", "sim", "analyze"}


def _setup_logging(verbose: bool) -> None:
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
    )


# --------------------------------------------------------------------- shared helpers
def _load_input(path: str) -> tuple[np.ndarray, int, float]:
    if not os.path.exists(path):
        raise FileNotFoundError(f"input not found: {path}")
    log.info("loading %s", path)
    x, sr = audioio.load(path, target_sr=WORK_SR)
    dur = len(audioio.to_mono(x)) / sr
    log.info("loaded: %.1fs, %d ch", dur, audioio.as_2d(x).shape[1])
    return x, sr, dur


def _load_reference(args: argparse.Namespace, sr: int) -> np.ndarray | None:
    ref_path = getattr(args, "reference", None)
    if not ref_path:
        return None
    if not os.path.exists(ref_path):
        raise FileNotFoundError(f"reference not found: {ref_path}")
    ref, _ = audioio.load(ref_path, target_sr=sr)
    log.info("loaded reference for match-EQ: %s", ref_path)
    return ref


def _build_config(args: argparse.Namespace) -> RemasterConfig:
    return RemasterConfig(
        do_dehiss=not args.no_dehiss,
        do_bwe=not args.no_bwe,
        do_match_eq=not args.no_match_eq,
        do_width=not args.no_width,
        target_lufs=args.target_lufs,
        tp_ceiling_db=args.ceiling,
        width_amount=args.width,
        noise_start=args.noise_start,
        noise_dur=args.noise_dur,
        bwe_rolloff_hz=args.rolloff,
        bwe_drive=args.bwe_drive,
        bwe_mix_db=args.bwe_mix_db,
        bwe_tilt_db_per_oct=args.bwe_tilt,
        bwe_max_delta_db=args.bwe_cap_db,
        bwe_noise_blend=args.bwe_noise,
    )


def _play_audio(path: str) -> None:
    if shutil.which("afplay"):
        player = ["afplay", path]
    elif shutil.which("ffplay"):
        player = ["ffplay", "-nodisp", "-autoexit", "-loglevel", "error", path]
    else:
        log.warning("no audio player found (afplay/ffplay); skipping playback")
        return
    log.info("playing (Ctrl-C to stop) ...")
    subprocess.run(player)


def _print_metrics(x: np.ndarray, result, sr: int, dur: float) -> None:
    out = result.audio
    info = result.info
    out_lufs = integrated_lufs(out, sr)
    out_lufs = out_lufs if np.isfinite(out_lufs) else float("nan")
    hf_in, hf_out = verify.hf_energy_db(x, sr), verify.hf_energy_db(out, sr)
    k_in, k_out = verify.spectral_kurtosis(x, sr), verify.spectral_kurtosis(out, sr)
    lines = [
        "",
        "  -- remaster report --------------------------------",
        f"    input LUFS         {info.get('input_lufs', float('nan')):.2f}",
        f"    output LUFS        {out_lufs:.2f}   (applied {info.get('lufs_gain_db', 0):+.2f} dB)",
        f"    input true peak    {info.get('true_peak_in_dbtp', float('nan')):.2f} dBTP",
        f"    HF energy 10k-Nyq  {hf_in:.2f} -> {hf_out:.2f} dB",
        f"    spectral kurtosis  {k_in:.2f} -> {k_out:.2f}  (musical-noise proxy)",
    ]
    if "rolloff_hz" in info:
        lines.append(f"    HF rolloff (used)  {info['rolloff_hz']:.0f} Hz")
    if "mono_sum_dev_db" in info:
        lines.append(f"    mono-sum deviation {info['mono_sum_dev_db']:+.2f} dB   (|x| < 1 dB = mono-safe)")
    lines.append("")
    lines.append(result.timer.report(dur))
    lines.append("  ---------------------------------------------------")
    print("\n".join(lines))


def _write_plots(x: np.ndarray, result, sr: int, out_dir: str, reference) -> None:
    os.makedirs(out_dir, exist_ok=True)
    sig = {"legacy (in)": x, "remastered": result.audio}
    if reference is not None:
        sig["modern ref"] = reference
    verify.plot_ltas(sig, sr, os.path.join(out_dir, "ltas.png"), "LTAS - before / after / reference")
    verify.plot_spectrogram(x, sr, os.path.join(out_dir, "spec_in.png"), "Input spectrogram")
    verify.plot_spectrogram(result.audio, sr, os.path.join(out_dir, "spec_out.png"), "Remastered spectrogram")
    if "eq_curve" in result.info:
        f, g = result.info["eq_curve"]
        verify.plot_eq_curve(f, g, os.path.join(out_dir, "match_eq.png"))


# --------------------------------------------------------------------------- commands
def _cmd_play(args: argparse.Namespace) -> int:
    x, sr, dur = _load_input(args.input)
    reference = _load_reference(args, sr)
    cfg = _build_config(args)

    t0 = time.perf_counter()
    result = remaster(x, sr, cfg, reference=reference)
    startup = time.perf_counter() - t0
    log.info("startup latency (full-track prebuffer): %.2fs for a %.1fs track", startup, dur)

    _print_metrics(x, result, sr, dur)
    if args.plots:
        _write_plots(x, result, sr, args.plots, reference)

    if args.keep:
        audioio.save(args.keep, result.audio, sr)
        log.info("kept remastered file: %s", args.keep)
        if not args.no_play:
            _play_audio(args.keep)
        return 0

    with tempfile.TemporaryDirectory() as td:
        tmp = os.path.join(td, "remastered.wav")
        audioio.save(tmp, result.audio, sr)
        if not args.no_play:
            _play_audio(tmp)
    return 0


def _cmd_remaster(args: argparse.Namespace) -> int:
    x, sr, dur = _load_input(args.input)
    reference = _load_reference(args, sr)
    cfg = _build_config(args)
    result = remaster(x, sr, cfg, reference=reference)

    out_path = args.output or f"{os.path.splitext(args.input)[0]}.remastered.wav"
    audioio.save(out_path, result.audio, sr)
    log.info("wrote %s", out_path)
    _print_metrics(x, result, sr, dur)
    if args.plots:
        _write_plots(x, result, sr, args.plots, reference)
        log.info("wrote verification plots to %s", args.plots)
    return 0


def _cmd_analyze(args: argparse.Namespace) -> int:
    orig, sr, _ = _load_input(args.input)
    if args.against:
        if not os.path.exists(args.against):
            raise FileNotFoundError(f"--against file not found: {args.against}")
        rem, _ = audioio.load(args.against, target_sr=sr)
        log.info("comparing against %s", args.against)
    else:
        reference = _load_reference(args, sr)
        rem = remaster(orig, sr, _build_config(args), reference=reference).audio
    out_dir = args.out or "out/analysis"
    metrics = analyze.compare(orig, rem, sr, out_dir)
    print(analyze.format_report(metrics))
    log.info("wrote comparison plots (LTAS, spectrograms, residual) to %s", out_dir)
    return 0


def _cmd_make_test(args: argparse.Namespace) -> int:
    os.makedirs(args.outdir, exist_ok=True)
    modern = synth.make_modern_reference(sr=args.sr, dur=args.dur)
    legacy = synth.degrade_to_legacy(modern, sr=args.sr)
    audioio.save(os.path.join(args.outdir, "modern_reference.wav"), modern, args.sr)
    audioio.save(os.path.join(args.outdir, "legacy_degraded.wav"), legacy, args.sr)
    log.info("wrote modern_reference.wav and legacy_degraded.wav to %s", args.outdir)
    return 0


def _cmd_bakeoff(args: argparse.Namespace) -> int:
    x, sr, _ = _load_input(args.input)
    entries = bakeoff.run_bakeoff(x, sr)
    print("\n  -- bandwidth-extension bake-off -------------------")
    print(bakeoff.format_table(entries))
    print("  ---------------------------------------------------")
    if args.out:
        os.makedirs(args.out, exist_ok=True)
        for e in entries:
            if e.name == "input":
                continue
            audioio.save(os.path.join(args.out, f"bwe_{e.name}.wav"), e.output, sr)
        verify.plot_ltas(
            {e.name: e.output for e in entries}, sr, os.path.join(args.out, "bwe_ltas.png"), "BWE LTAS"
        )
        log.info("wrote bake-off outputs + LTAS to %s", args.out)
    return 0


def _cmd_sim(args: argparse.Namespace) -> int:
    res = sim.simulate_process_ahead(args.rtf, args.headstart, args.duration)
    if res.starved:
        verdict = "STARVES (stutter)"
    elif args.rtf < 1:
        verdict = "stable (buffer grows)"
    else:
        verdict = "stable (constant margin)"
    max_dur = sim.max_streamable_duration(args.rtf, args.headstart)
    max_str = "unbounded (rtf < 1)" if max_dur == float("inf") else f"{max_dur:.0f}s"
    print(
        f"\n  process-ahead: rtf={args.rtf}  headstart={args.headstart}s  duration={args.duration}s\n"
        f"    buffer at start : {res.buffer_s[0]:.2f}s\n"
        f"    min buffer      : {res.min_buffer_s:.2f}s\n"
        f"    verdict         : {verdict}\n"
        f"    max streamable  : {max_str}"
    )
    if args.plot:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt

        plt.figure(figsize=(9, 4))
        plt.plot(res.t, res.buffer_s)
        plt.axhline(1.0, color="r", ls="--", alpha=0.6, label="1 s low-water mark")
        plt.xlabel("playback time (s)")
        plt.ylabel("buffer depth (s)")
        plt.title(f"Process-ahead buffer (rtf={args.rtf}, headstart={args.headstart}s)")
        plt.legend()
        plt.grid(alpha=0.3)
        plt.tight_layout()
        plt.savefig(args.plot, dpi=110)
        plt.close()
        log.info("wrote %s", args.plot)
    return 0


# ---------------------------------------------------------------------------- parser
def _add_processing_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("input")
    p.add_argument("--reference", help="modern track to match tonal balance to (match-EQ)")
    p.add_argument("--target-lufs", type=float, default=-14.0)
    p.add_argument("--ceiling", type=float, default=-1.0, help="true-peak ceiling dBTP")
    p.add_argument("--width", type=float, default=0.4, help="stereo width amount 0..1")
    p.add_argument("--rolloff", type=float, default=None, help="force BWE rolloff Hz (default auto)")
    p.add_argument("--bwe-mix-db", type=float, default=-15.0,
                   help="BWE level vs source band (lower = subtler highs; default -15)")
    p.add_argument("--bwe-drive", type=float, default=1.5,
                   help="BWE harmonic drive (lower = cleaner; default 1.5)")
    p.add_argument("--bwe-tilt", type=float, default=-9.0,
                   help="BWE HF decay dB/octave (steeper = less top sizzle; default -9)")
    p.add_argument("--bwe-cap-db", type=float, default=8.0,
                   help="per-octave cap on the synthesized lift (lower reins in bright content; default 8)")
    p.add_argument("--bwe-noise", type=float, default=0.0,
                   help="stochastic 'air' blend 0..1 (higher = less metallic, more airy; default 0)")
    p.add_argument("--noise-start", type=float, default=None, help="noise-only segment start (s)")
    p.add_argument("--noise-dur", type=float, default=None, help="noise-only segment duration (s)")
    p.add_argument("--no-dehiss", action="store_true")
    p.add_argument("--no-bwe", action="store_true")
    p.add_argument("--no-match-eq", action="store_true")
    p.add_argument("--no-width", action="store_true")
    p.add_argument("--plots", help="dir to write verification plots")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="legacy-remaster", description=__doc__.splitlines()[0])
    p.add_argument("-v", "--verbose", action="store_true", help="debug logging")
    sub = p.add_subparsers(dest="command", required=True)

    play = sub.add_parser("play", help="remaster a track and play it")
    _add_processing_opts(play)
    play.add_argument("--keep", help="also save the remastered WAV to this path")
    play.add_argument("--no-play", action="store_true", help="process only, don't play")
    play.set_defaults(func=_cmd_play)

    rem = sub.add_parser("remaster", help="remaster a track to a WAV file")
    _add_processing_opts(rem)
    rem.add_argument("-o", "--output", help="output WAV (default: <input>.remastered.wav)")
    rem.set_defaults(func=_cmd_remaster)

    m = sub.add_parser("make-test", help="synthesize modern + legacy test fixtures")
    m.add_argument("outdir")
    m.add_argument("--sr", type=int, default=WORK_SR)
    m.add_argument("--dur", type=float, default=8.0)
    m.set_defaults(func=_cmd_make_test)

    an = sub.add_parser("analyze", help="compare original vs remastered (plots + metrics)")
    _add_processing_opts(an)
    an.add_argument("--against", help="compare against an already-remastered file (skip internal remaster)")
    an.add_argument("--out", help="dir for comparison plots (default out/analysis)")
    an.set_defaults(func=_cmd_analyze)

    b = sub.add_parser("bakeoff", help="compare bandwidth-extension methods")
    b.add_argument("input")
    b.add_argument("--out", help="dir to write per-method WAVs + LTAS plot")
    b.set_defaults(func=_cmd_bakeoff)

    s = sub.add_parser("sim", help="process-ahead buffer simulation")
    s.add_argument("--rtf", type=float, default=0.3)
    s.add_argument("--headstart", type=float, default=5.0)
    s.add_argument("--duration", type=float, default=240.0)
    s.add_argument("--plot", help="write buffer-depth plot to this path")
    s.set_defaults(func=_cmd_sim)
    return p


GLOBAL_FLAGS = {"-v", "--verbose"}


def _inject_default_command(argv: list[str]) -> list[str]:
    """A bare path (no subcommand) defaults to `play`: `legacy-remaster track.mp3`.

    Robust to flags that take values (e.g. `--reference x.flac old.mp3`): if no known
    subcommand appears anywhere, insert `play` right after any leading global flags, so the
    rest of the args (path + that command's flags) are parsed by the `play` subparser.

    Only LEADING global flags are handled: a global flag (-v) must precede the path, not be
    interleaved after a processing flag (use the explicit `play` subcommand for exotic orders)."""
    if not argv or argv[0] in ("-h", "--help"):
        return argv
    if any(tok in SUBCOMMANDS for tok in argv):
        return argv
    i = 0
    while i < len(argv) and argv[i] in GLOBAL_FLAGS:
        i += 1
    return [*argv[:i], "play", *argv[i:]]


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    argv = _inject_default_command(argv)
    args = build_parser().parse_args(argv)
    _setup_logging(args.verbose)
    try:
        return args.func(args)
    except KeyboardInterrupt:
        return 130
    except Exception as exc:
        # self-classifying message (type + text); full traceback only with -v
        log.error("%s: %s", type(exc).__name__, exc)
        if args.verbose:
            raise
        return 1


if __name__ == "__main__":
    sys.exit(main())
