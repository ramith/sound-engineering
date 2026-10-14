# Exhaustive interleaving model (sequentially consistent) of the fix's RenderGate (fix/render-gate-liveness
# RenderGate.h): bit R (render inside) + bit C (closed). Render loop: tryEnter = CAS 0->R; leave = fetch_and ~R.
# Control: close = requestClose (fetch_or C, returns old R) + awaitQuiet (poll R; may time out -> open()).
# Checks (1) exclusion: render inside while the control uses the source after a SUCCESSFUL close;
# (2) progress: once requestClose is done, the render never starts a NEW pass until open();
# (3) teardown: what a FAILED close leaves behind (the fix's close() reopens on timeout).
from collections import deque
def explore(teardown_variant, rounds=3):
    # state: (gate, rpc, cpc, rounds_left, newpass_after_request, freed)
    # rpc: 0 idle (about to tryEnter), 1 inside (using the source)
    # cpc: 0 idle, 1 awaiting quiet, 2 using source (seek) / tearing down, 3 done
    init = (0, 0, 0, rounds, False, False)
    seen = {init}; q = deque([init]); bad = []
    while q:
        g, rpc, cpc, rl, newpass, freed = q.popleft()
        if rpc >= 1 and cpc == 2: bad.append(('overlap: render inside while control uses the source', g, rpc, cpc))
        if rpc == 1 and freed: bad.append(('UAF by the ONE pass that was stuck inside at the timeout', g, rpc, cpc))
        if rpc == 2: bad.append(('UAF by a NEW pass that entered AFTER teardown freed the source', g, rpc, cpc))
        nxt = []
        # render
        if rpc == 0:
            if g == 0:
                nxt.append((g | 1, 2 if freed else 1, cpc, rl, newpass or cpc == 1, freed))   # entered (2 = a NEW pass after the free)
            else:
                nxt.append((g, 0, cpc, rl, newpass, freed))                   # turned away
        else:
            nxt.append((g & ~1, 0, cpc, rl, newpass, freed))                  # leave (from 1 or 2)
        # control
        if cpc == 0 and rl > 0:
            old = g; g2 = g | 2
            nxt.append((g2, rpc, 1 if old & 1 else 2, rl, newpass, freed))   # requestClose
        elif cpc == 1:
            if not (g & 1): nxt.append((g, rpc, 2, rl, newpass, freed))      # quiet -> proceed
            else:
                # timeout branch
                if teardown_variant == 'fix-close-in-teardown':
                    # close() reopens (open()), returns false; teardown CONTINUES and frees the source
                    nxt.append((g & ~2, rpc, 3, 0, newpass, True))
                elif teardown_variant == 'request-no-reopen':
                    # requestClose kept, no reopen; teardown continues and frees (only the stuck pass is at risk)
                    nxt.append((g, rpc, 3, 0, newpass, True))
                else:  # seek: close() reopens, seek refused, nothing freed
                    nxt.append((g & ~2, rpc, 0, rl - 1, newpass, freed))
        elif cpc == 2:
            if teardown_variant in ('fix-close-in-teardown', 'request-no-reopen'):
                nxt.append((g, rpc, 3, 0, newpass, True))                     # successful teardown frees, gate stays closed
            else:
                nxt.append((g & ~2, rpc, 0, rl - 1, newpass, freed))          # seek done -> open()
        for s in nxt:
            if s not in seen: seen.add(s); q.append(s)
    starved = any(s[4] for s in seen)
    return len(seen), bad, starved
for v in ('seek', 'fix-close-in-teardown', 'request-no-reopen'):
    n, bad, newpass = explore(v)
    kinds = sorted({b[0] for b in bad})
    print(f"{v:22s}: {n} states; render started a NEW pass while a close was pending: {newpass}; violations: {kinds or 'none'}")
