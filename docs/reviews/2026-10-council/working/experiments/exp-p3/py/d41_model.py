# Exhaustive interleaving model (sequentially consistent) of GaplessSource @ f93b08e:
#   RT  : pullFloat's true-EOF branch (GaplessSource.cpp:273-310)
#   CTRL: the bridge's re-arm = clearNext() then armNext(C) (GaplessSource.cpp:117-185),
#         optionally the poll plane's reapRetired() in between.
# Start: slot0 = A (active, at EOF), slot1 = B (armed). Each step below is one atomic access.
from itertools import product
def run(with_poll_reap):
    init = dict(active=0, armed=1, retired=None, ended=False, src=['A', 'B'], destroyed=frozenset(),
                rpc=0, cur=None, nxt=None, rt_heard=None,
                cpc=0, cleared=None, reaped=None, a_act=None, a_ret=None, slot=None, arm_result=None, poll_done=not with_poll_reap)
    def key(s): return tuple(sorted((k, v if not isinstance(v, list) else tuple(v)) for k, v in s.items()))
    seen = set(); stack = [init]; outcomes = {}; bad = []
    while stack:
        s = stack.pop()
        k = key(s)
        if k in seen: continue
        seen.add(k)
        nxt_states = []
        # ---- RT ----
        if s['rpc'] == 0: t = dict(s); t['cur'] = s['active']; t['rpc'] = 1; nxt_states.append(t)
        elif s['rpc'] == 1: t = dict(s); t['rpc'] = 99 if s['ended'] else 2; nxt_states.append(t)
        elif s['rpc'] == 2: t = dict(s); t['nxt'] = s['armed']; t['armed'] = None; t['rpc'] = 3; nxt_states.append(t)
        elif s['rpc'] == 3:
            t = dict(s)
            if s['nxt'] is None: t['ended'] = True; t['rpc'] = 99
            else: t['rpc'] = 4
            nxt_states.append(t)
        elif s['rpc'] == 4: t = dict(s); t['retired'] = s['cur']; t['rpc'] = 5; nxt_states.append(t)
        elif s['rpc'] == 5: t = dict(s); t['active'] = s['nxt']; t['rpc'] = 6; nxt_states.append(t)
        elif s['rpc'] == 6:   # nxt->source->pullFloat : what is heard at the seam
            t = dict(s); name = s['src'][s['nxt']]
            if name in s['destroyed'] or name is None: bad.append(('RT pulls a destroyed/null source at the seam', name))
            t['rt_heard'] = name; t['rpc'] = 99; nxt_states.append(t)
        # ---- CTRL ----
        c = s['cpc']
        if c == 0:   # clearNext: exchange
            t = dict(s); t['cleared'] = s['armed']; t['armed'] = None; t['cpc'] = 1; nxt_states.append(t)
        elif c == 1:   # clearNext: destroy what it took
            t = dict(s)
            if s['cleared'] is not None: t['destroyed'] = s['destroyed'] | {s['src'][s['cleared']]}; t['src'] = list(s['src']); t['src'][s['cleared']] = None
            t['cpc'] = 2 if s['poll_done'] else 10; nxt_states.append(t)
        elif c == 10:   # poll plane's reapRetired between the clear and the arm
            t = dict(s); r = s['retired']; t['retired'] = None
            if r is not None: t['destroyed'] = s['destroyed'] | {s['src'][r]}; t['src'] = list(s['src']); t['src'][r] = None
            t['poll_done'] = True; t['cpc'] = 2; nxt_states.append(t)
        elif c == 2:   # armNext: armed != null ?
            t = dict(s); t['cpc'] = 98 if s['armed'] is not None else 3; t['arm_result'] = 'refused-occupied' if s['armed'] is not None else None; nxt_states.append(t)
        elif c == 3:   # ended ?
            t = dict(s); t['cpc'] = 98 if s['ended'] else 4; t['arm_result'] = 'refused-ended' if s['ended'] else None; nxt_states.append(t)
        elif c == 4:   # reapRetired: exchange retired
            t = dict(s); t['reaped'] = s['retired']; t['retired'] = None; t['cpc'] = 5; nxt_states.append(t)
        elif c == 5:   # reapRetired: destroy it
            t = dict(s)
            if s['reaped'] is not None:
                nm = s['src'][s['reaped']]
                if s['rpc'] in (4, 5, 6) and s['reaped'] == s['nxt']: bad.append(('reap destroys the track the RT is seaming into', nm))
                t['destroyed'] = s['destroyed'] | {nm}; t['src'] = list(s['src']); t['src'][s['reaped']] = None
            t['cpc'] = 6; nxt_states.append(t)
        elif c == 6:   # freeSlotForArm: load active
            t = dict(s); t['a_act'] = s['active']; t['cpc'] = 7; nxt_states.append(t)
        elif c == 7:   # freeSlotForArm: load retired, pick
            t = dict(s); t['a_ret'] = s['retired']
            free = [i for i in (0, 1) if i != s['a_act'] and i != s['retired']]
            if not free: t['arm_result'] = 'refused-no-free-slot (ended=%s)' % s['ended']; t['cpc'] = 98
            else: t['slot'] = free[0]; t['cpc'] = 8
            nxt_states.append(t)
        elif c == 8:   # slot->source = C  (the old unique_ptr in that slot is destroyed here)
            t = dict(s); old = s['src'][s['slot']]; t['src'] = list(s['src'])
            if old is not None:
                t['destroyed'] = s['destroyed'] | {old}
                if s['rpc'] in (4, 5, 6) and s['nxt'] == s['slot']: bad.append(('armNext overwrites the slot the RT is seaming into', old))
                if s['active'] == s['slot'] and s['rpc'] == 99: bad.append(('armNext overwrites the ACTIVE slot', old))
            t['src'][s['slot']] = 'C'; t['cpc'] = 9; nxt_states.append(t)
        elif c == 9:
            t = dict(s); t['armed'] = s['slot']; t['arm_result'] = 'armed'; t['cpc'] = 98; nxt_states.append(t)
        if not nxt_states:
            o = (s['rt_heard'], s['ended'], s['arm_result'], 'C armed in the ACTIVE slot' if s['armed'] is not None and s['armed'] == s['active'] else '')
            outcomes[o] = outcomes.get(o, 0) + 1
        stack.extend(nxt_states)
    return len(seen), outcomes, bad
for poll in (False, True):
    n, outcomes, bad = run(poll)
    print(f"--- re-arm = clearNext(); {'poll reapRetired(); ' if poll else ''}armNext(C)  [{n} states]")
    for o, cnt in sorted(outcomes.items(), key=lambda x: str(x)):
        print(f"   heard at seam={o[0]!s:5} ended={o[1]!s:5} arm={o[2]!s:38} {o[3]}")
    kinds = {}
    for b in bad: kinds[b[0]] = kinds.get(b[0], 0) + 1
    for kk, v in kinds.items(): print(f"   VIOLATION: {kk} ({v} traces)")
