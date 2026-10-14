#!/bin/bash
# For each sample chunk: the main thread's heaviest blocking frames (sync waits, CoreAudio, locks).
S="$1"
for f in "$S"/chunk-*.txt; do
  main=$(awk '/DispatchQueue_1: com.apple.main-thread/{p=1;print;next} p&&/^    [0-9]+ Thread_/{exit} p' "$f")
  hit=$(echo "$main" | grep -E "__DISPATCH_WAIT_FOR_QUEUE__|_dispatch_sync_f_slow|_dispatch_lane_barrier_sync|semaphore_wait|_pthread_mutex_firstfit_lock_wait|__ulock_wait|AudioObject(Get|Set)PropertyData|HALC_|AVAudioEngine|AVAudioPlayerNode" | sed -E 's/^[ +!:|]*//' | sort -t' ' -k1 -nr | head -3)
  [ -n "$hit" ] && { echo "== $(basename $f) start $(cat ${f%.txt}.start 2>/dev/null)"; echo "$hit" | cut -c1-170; }
done
