import numpy as np, sys, os
sys.argv=[sys.argv[0]]
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'t_pred.py')).read().split("progs = {}")[0])
progs = {}
for f0 in (40.0, 63.0, 80.0):
    s = 0.25*np.sin(2*np.pi*f0*t); progs[f'sine {f0} + pink-30'] = [s+0.01*pink(n), s+0.01*pink(n)]
cmds = {}
for b,g in [(5,6.),(5,-6.),(3,6.),(6,6.),(4,3.)]: cmds[f'b{b}{g:+.0f}'] = np.eye(31)[b]*g
cmds['adjacent +6/-6 (b4,b5)'] = np.eye(31)[4]*6 - np.eye(31)[5]*6
C = np.array(list(cmds.values()), np.float32)
for pname, xs in progs.items():
    save(xs); C.tofile(E+'/pc.f32')
    subprocess.run([E+'/proh', str(fs), str(fs), '2', E+'/sig.f32', E+'/pc.f32', E+'/pred.f64'], check=True)
    res = np.fromfile(E+'/pred.f64')[2:].reshape(-1,3); l0 = lufs(xs)
    for (cname, cmd), (ok, dl, dl4) in zip(cmds.items(), res):
        np.asarray(cmd, np.float32).tofile(E+'/c1.f32')
        subprocess.run([E+'/eqh','apply',str(fs),'2',E+'/sig.f32',E+'/c1.f32',E+'/sigo.f32'],check=True)
        yo = np.fromfile(E+'/sigo.f32',np.float32).reshape(2,-1); true = lufs([yo[0],yo[1]]) - l0
        print(f'{pname:22s} {cname:24s} true {true:+7.3f}  pred {dl:+7.3f}  err {dl-true:+.3f}  (step4 {dl4:+.3f})')
