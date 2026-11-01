import Foundation
import simd

/// Beasts of the wilds. So far only the wolf: a grey wolf, drawn like the people facing
/// south (towards the viewer) about (0, 0), with +y towards its nose.
enum BeastArt {
    static func wolf(step: Int) -> Model {
        var m = Model()
        m.seed = 0x3017F
        let fur = Paint(0x7A7470, .hair, jitter: 0.08, shine: 0.05)
        let dark = Paint(0x48443F, .hair, jitter: 0.08)
        let pale = Paint(0xC0B6A8, .hair, jitter: 0.06)
        let black = Paint(0x1A1614)
        let amber = Paint(0xE0A020, shine: 0.6)
        let swing = Float(step) * 1.8
        // Legs, the near pair of each end swinging against the other.
        for (y, side, s) in [(4.6 as Float, -1 as Float, swing), (4.6, 1, -swing), (-5, -1, -swing), (-5, 1, swing)] {
            let x = side * 1.9
            m.rod(V3(x, y, 8), V3(x, y + s, 1.2), 1.1, fur)
            m.ball(x, y + s + 0.4, 0.9, 1.1, dark)
        }
        // Body: haunch, barrel and deep chest, a dark saddle and a pale belly.
        m.blob(0, -5, 9.6, 3.2, 3.2, 3.4, fur)
        m.blob(0, 0, 9.4, 3.3, 7, 3.5, fur)
        m.blob(0, 4.4, 10.2, 3.6, 3.4, 4, fur)
        m.blob(0, -1, 12.3, 2.6, 6.2, 1.3, dark)
        m.blob(0, 1.5, 6.6, 2.4, 5.4, 1.6, pale)
        m.blob(0, 6.6, 9.6, 2.2, 1.6, 2.8, pale)
        // Tail, hanging low.
        m.rod(V3(0, -7.6, 11), V3(0, -11.4, 6.6), 1.4, fur)
        m.blob(0, -12, 5.6, 1.4, 1.6, 1.8, dark)
        // Neck and head, with a long muzzle, pricked ears and amber eyes.
        m.rod(V3(0, 6, 11.4), V3(0, 8.6, 13.6), 2.5, fur)
        m.ball(0, 9.6, 14.2, 2.8, fur)
        m.blob(0, 9.2, 15.6, 2.2, 2, 1.2, dark)
        m.blob(0, 12.6, 13.1, 1.4, 2.6, 1.3, fur)
        m.blob(0, 12.4, 12.4, 1.2, 2.2, 0.8, pale)
        m.ball(0, 14.9, 13.4, 0.65, black)
        for side: Float in [-1, 1] {
            m.rod(V3(side * 1.5, 8.8, 16), V3(side * 1.9, 8.4, 18.4), 0.75, dark)
            m.ball(side * 1.25, 11.7, 14.8, 0.45, amber)
        }
        return m
    }

    static func wolfModel(facing: Direction, step: Int) -> Model {
        Posing.stand(wolf(step: step), facing: facing, scale: V3(repeating: 1))
    }
}
