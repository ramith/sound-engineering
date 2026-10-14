// Reference tone (AudioEngineBridge+ReferenceTone.swift:37-59) reproduced: Float angle, vForce.sin, gain 0.3.
import Accelerate
let n = 240000
let inc = 2.0 * Float.pi * Float(1000) / Float(48000)
var ang = [Float](repeating: 0, count: n)
for i in 0 ..< n { ang[i] = inc * Float(i) }
let y = vForce.sin(ang).map { $0 * 0.3 }
func report(_ lo: Int, _ hi: Int) {
    var e2 = 0.0, s2 = 0.0, pk = 0.0
    for k in lo ..< hi { let ideal = 0.3 * sin(2 * Double.pi * 1000 * Double(k) / 48000); let e = Double(y[k]) - ideal; e2 += e * e; s2 += ideal * ideal; pk = max(pk, abs(e)) }
    print(String(format: "frames %d-%d: error rms %.1f dB re tone, peak %.1f dB re 0.3", lo, hi, 10 * log10(e2 / s2), 20 * log10(pk / 0.3)))
}
report(0, 4800); report(n - 4800, n)
