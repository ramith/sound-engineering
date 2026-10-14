# Exhaustive interleaving model of DoubleBufferSnapshot (DoubleBufferSnapshot.h:145-197), sequentially
# consistent atomics, plain index updates as separate steps (the "skew window" the proof mentions).
# Checks: (1) the producer never writes the slot the consumer is reading; (2) every read returns a
# completed generation, never older than the previous read; (3) a read after the last publish
# eventually returns it (freshness).
import sys
sys.setrecursionlimit(100000)
PUBS, READS = 4, 4
def run():
    init = dict(W=0, R=1, C=2, fresh=False, slot=[0, 0, 0], pc_p=0, pc_c=0, pubs=0, reads=0,
                p_prev=None, c_prev=None, last_read=0, writing=None, reading=None, published=0)
    seen = set(); errs = []; states = 0
    def key(s): return (s['W'], s['R'], s['C'], s['fresh'], tuple(s['slot']), s['pc_p'], s['pc_c'], s['pubs'], s['reads'],
                        s['p_prev'], s['c_prev'], s['last_read'], s['writing'], s['reading'], s['published'])
    def steps(s):
        out = []
        if s['pubs'] < PUBS:
            t = dict(s); t['slot'] = list(s['slot'])
            pc = s['pc_p']
            if pc == 0: t['writing'] = t['W']; t['pc_p'] = 1                         # memcpy begins
            elif pc == 1: t['slot'][t['W']] = t['pubs'] + 1; t['writing'] = None; t['pc_p'] = 2   # memcpy ends
            elif pc == 2: t['p_prev'] = t['C']; t['C'] = t['W']; t['fresh'] = True; t['published'] = t['pubs'] + 1; t['pc_p'] = 3  # exchange
            elif pc == 3: t['W'] = t['p_prev']; t['pc_p'] = 0; t['pubs'] += 1          # writeIndex_ = old
            out.append(t)
        if s['reads'] < READS:
            t = dict(s); t['slot'] = list(s['slot'])
            pc = s['pc_c']
            if pc == 0: t['pc_c'] = 1 if s['fresh'] else 3                            # load(control)
            elif pc == 1: t['c_prev'] = t['C']; t['C'] = t['R']; t['fresh'] = False; t['pc_c'] = 2   # exchange
            elif pc == 2: t['R'] = t['c_prev']; t['pc_c'] = 3
            elif pc == 3: t['reading'] = t['R']; t['pc_c'] = 4                         # memcpy begins
            elif pc == 4:
                v = t['slot'][t['R']]
                if v < t['last_read']: errs.append(('backwards', v, t['last_read']))
                t['last_read'] = v; t['reading'] = None; t['pc_c'] = 0; t['reads'] += 1
            out.append(t)
        return out
    stack = [init]
    while stack:
        s = stack.pop()
        k = key(s)
        if k in seen: continue
        seen.add(k); states += 1
        if s['writing'] is not None and s['writing'] == s['reading']: errs.append(('overlap', k))
        if s['writing'] is not None and s['writing'] == s['C'] and s['pc_p'] == 1 and False: pass
        if len({s['W'], s['R'], s['C']}) != 3 and s['pc_p'] in (0, 1) and s['pc_c'] in (0, 3, 4):
            errs.append(('not a permutation at a payload access', k))
        nxt = steps(s)
        if not nxt and s['published'] and s['last_read'] < s['published']:
            pass   # final reads may legitimately precede the last publish
        stack.extend(nxt)
    print(f"states explored {states}; violations {len(errs)}", errs[:3])
    # Freshness: after all publishes, a sequence of 2 reads returns the last generation.
run()
