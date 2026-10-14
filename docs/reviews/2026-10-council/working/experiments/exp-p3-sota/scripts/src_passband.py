import sys, os
sys.argv = [sys.argv[0]]
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
exec(open(os.path.join(HERE, 'src_quality.py')).read().split("cases = [")[0])
for fi in [44100, 96000]:
    print(f'== {fi} -> 48000 passband (dB re input) ==')
    for name in ['AVAC max Normal (prod)', 'AVAC max Mastering', 'AVAC max MinimumPhase', 'soxr VHQ']:
        fn = CONVS[name]; row = []
        for f in [12000, 15000, 16000, 17000, 18000, 18500, 19000, 19500, 20000]:
            y = fn(tone(f, fi), fi, 48000); P, df = spectrum(y, 48000)
            row.append(f'{f/1000:g}k {db(tone_amp(P, df, f)/0.5):+.2f}')
        print(f'  {name:24s} ' + ' | '.join(row))
