#if DEBUG
    import EQEditKit
    import Foundation

    // MARK: - Picture-sheet fixture data: the EQ (Sprint EQ, EQ3)

    extension SheetFixture {
        /// The band the EQ drag world drags (4 kHz, up from Warm's 0 dB) and where to.
        private static let dragSample = EQGraphDrag(band: 23, requestedDb: 5)
        /// The ceiling world's drag: 315 Hz asked past the +12 dB ceiling, which holds it.
        private static let ceilingSample = EQGraphDrag(band: 12, requestedDb: 14.2)
        /// The ring world's keyboard cursor: 80 Hz, a point the Tone layer holds at the ceiling ("limited").
        private static let ringBand = 6

        /// Seeds the EQ for `variant`: every world plays "Warm · Edited" with My Presets saved and the
        /// engine running; each EQ world then puts the screen in its one state — through the view
        /// model's own verbs, so a sheet shows what the app would.
        static func seedEQ(_ eq: EQViewModel, audio: AudioViewModel, for variant: SheetVariant) {
            audio.isEngineReady = variant != .eqEngine
            eq.seedRenderFixture(state: variant == .ring ? toneLimitedState() : editedWarm(),
                                 myPresets: myPresets(many: variant == .eqMany))
            switch variant {
            case .eqDrag: stroke(eq, dragSample)
            case .eqCeiling: stroke(eq, ceilingSample)
            case .eqOff: eq.isOn = false
            case .eqCompare: eq.beginCompare()
            case .eqPure: audio.signalPath.path = .pure
            default: break
            }
        }

        /// The graph's own state for `variant` (its drag, its keyboard cursor), which the graph seeds on
        /// appear.
        static func eqGraphSeed(for variant: SheetVariant) -> SheetEQGraph {
            switch variant {
            case .eqDrag: SheetEQGraph(drag: dragSample)
            case .eqCeiling: SheetEQGraph(drag: ceilingSample)
            case .ring: SheetEQGraph(cursorBand: ringBand)
            default: SheetEQGraph()
            }
        }

        /// A drag left under way: the view model's stroke, as the pointer would run it.
        private static func stroke(_ eq: EQViewModel, _ sample: EQGraphDrag) {
            eq.beginStroke()
            eq.updateStroke(band: sample.band, db: Float(sample.requestedDb))
        }

        /// "Warm · Edited": Warm with a dip drawn in around 3 kHz (a real stroke, neighbours following).
        private static func editedWarm() -> EQState {
            var stroke = EQStroke(start: EQCurve(points: EQBuiltInPreset.warm.points))
            return EQState(preset: .builtIn(.warm), curve: stroke.curve(movingTo: 22, db: -1.5))
        }

        /// Warm under a +6 dB Bass Tone: the low points ask past +12 dB and are held there ("limited").
        /// Decoded from the stored form — the Tone verbs are the Tone card's (EQ3t).
        private static func toneLimitedState() -> EQState {
            let base = EQBuiltInPreset.warm.points.map { "\($0)" }.joined(separator: ",")
            let json = #"{"base":["# + base + #"],"tone":[6,0,0,0,0]}"#
            let curve = try? JSONDecoder().decode(EQCurve.self, from: Data(json.utf8))
            return EQState(preset: .builtIn(.warm), curve: curve)
        }

        /// My Presets: the design's two, or twelve with a 40-character name (the list scrolls).
        private static func myPresets(many: Bool) -> [String: [Float]] {
            let names = many
                ? ["Late Night", "Podcast", "AirPods walk", "Audiobook", "Bass practice", "Car", "Classical",
                   "Jazz club", "Movie night", "Studio monitors", "Vinyl rip", longPresetName]
                : ["Late Night", "Podcast"]
            return Dictionary(uniqueKeysWithValues: names.enumerated().map { index, name in
                (name, presetShape(index))
            })
        }

        /// 40 characters: the row truncates it, with the full name in its tooltip.
        private static let longPresetName = "Grandma's kitchen radio, Sunday mornings"

        /// A plausible saved curve, different per `index`: a low shelf and a treble tilt.
        private static func presetShape(_ index: Int) -> [Float] {
            let low = Float(index % 4) * 2 - 2
            let high = Float((index + 2) % 5) * 1.5 - 3
            return (0 ..< EQBands.count).map { band in
                let position = Float(band) / Float(EQBands.count - 1)
                return ((low * (1 - position) * (1 - position) + high * position * position) * 2).rounded() / 2
            }
        }
    }
#endif
