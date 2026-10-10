#!/bin/sh
# Re-runs every v2 measurement quoted in ../dsp-plan-v2.md (about 6 minutes). Run from this folder: sh run_all.sh
set -e
mkdir -p results tmp
(cd cpp && clang++ -std=c++20 -O3 -mcpu=native tdsim.cpp -o tdsim && clang++ -std=c++20 -O3 -mcpu=native bench_v2.cpp -o bench_v2 \
  && clang++ -std=c++20 -O2 -mcpu=native fz_check.cpp -o fz_check)
python3 solver_v2.py   > /dev/null          # results/s1_solver_passes.txt
python3 ultrasonic.py  > /dev/null          # results/s1b_ultrasonic.txt
python3 trans_fd.py    > /dev/null          # results/s2_transition_fd.txt (+ adv_pair_S1/S2.npy)
python3 trans_fd2.py   > /dev/null          # results/s2b_transition_fd_metrics.txt
python3 trans_td.py    > /dev/null          # results/s2c_transition_td.txt
python3 trans_td2.py   > results/s2d_transition_td_mitigation.log
python3 trans_td3.py   > /dev/null          # results/s2e_tau_sweep_drag.txt
python3 trans_td4.py   > /dev/null          # results/s2f_tau40_both.txt
python3 loudness_v2.py > /dev/null          # results/s4_loudness.txt (+ rows json)
python3 predictor_res.py > /dev/null        # results/s4b_predictor_resolution.txt
python3 shortterm.py   > /dev/null          # results/s4c_shortterm.txt
python3 hopsum.py      > /dev/null          # results/s4d_hopsum.txt
cpp/bench_v2 > results/s5_cpu_s2.txt
python3 guards.py 2>/dev/null > /dev/null   # results/s7_guards.txt
cpp/fz_check > results/s7_fz_check.txt
python3 limiter_i0.py > /dev/null        # results/s5b_limiter_intensity0.txt
rm -rf tmp __pycache__
echo done
