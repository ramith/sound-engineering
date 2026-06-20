"""CLI parsing — the bare-path -> `play` injection and config plumbing (no audio needed)."""
import pytest

from remaster import cli


@pytest.mark.parametrize(
    "argv,expected_first",
    [
        (["song.mp3"], "play"),                       # bare path -> play
        (["-v", "song.mp3"], "-v"),                    # global flag stays first; play inserted after
        (["play", "song.mp3"], "play"),                # explicit subcommand untouched
        (["remaster", "song.mp3"], "remaster"),
        (["--reference", "m.flac", "old.mp3"], "play"),  # M1: flag-before-path must still work
        (["make-test", "out"], "make-test"),
        (["sim"], "sim"),
        (["-h"], "-h"),
    ],
)
def test_inject_default_command(argv, expected_first):
    out = cli._inject_default_command(list(argv))
    assert out[0] == expected_first
    if argv[0] not in cli.SUBCOMMANDS and argv[0] not in ("-h", "--help"):
        assert "play" in out


def test_inject_flag_before_path_parses():
    """The previously-broken `--reference X path` ordering now parses correctly."""
    argv = cli._inject_default_command(["--reference", "m.flac", "old.mp3"])
    args = cli.build_parser().parse_args(argv)
    assert args.command == "play"
    assert args.input == "old.mp3"
    assert args.reference == "m.flac"


def test_inject_verbose_before_path():
    argv = cli._inject_default_command(["-v", "old.mp3"])
    args = cli.build_parser().parse_args(argv)
    assert args.verbose and args.command == "play" and args.input == "old.mp3"


def test_build_config_roundtrips_flags():
    args = cli.build_parser().parse_args(
        ["remaster", "x.wav", "--target-lufs", "-16", "--no-bwe", "--no-width", "--width", "0.6"]
    )
    cfg = cli._build_config(args)
    assert cfg.target_lufs == -16
    assert cfg.do_bwe is False and cfg.do_width is False
    assert cfg.width_amount == 0.6
    assert cfg.do_dehiss is True  # not disabled
