/// `sin`, `cos`, and `atan2` that give the same bits on every machine, for anything routing feeds
/// into the simulation, such as a Sim's facing.
///
/// The platform's own functions are accurate but not identical everywhere: each C library rounds
/// its last bit its own way. These use only addition, subtraction, multiplication, division,
/// rounding to an integer, and the exact remainder, which IEEE 754 defines bit for bit, in a fixed
/// order. They agree with the platform's to within about 1e-15 for the values a lot uses.
///
/// Not a number in gives not a number out. Infinities give `nan` for `sin` and `cos`, and the
/// usual limits for `atan2`.
public enum DeterministicMath {
    /// π, and π/2 split in two (a head with trailing zeros, and the rest), so an argument can be
    /// reduced without losing bits.
    static let pi = 3.141592653589793
    static let halfPi = 1.5707963267948966
    static let quarterPi = 0.7853981633974483
    private static let halfPiHead = 1.57079632673412561417
    private static let halfPiTail = 6.07710050650619224932e-11
    private static let twoOverPi = 0.636619772367581382433
    private static let twoPi = 6.283185307179586
    /// tan(π/8), where `atan` splits its range.
    private static let tanEighthPi = 0.41421356237309503

    public static func sin(_ x: Double) -> Double {
        guard let (r, quadrant) = reduce(x) else { return .nan }
        switch quadrant {
        case 0: return sinKernel(r)
        case 1: return cosKernel(r)
        case 2: return -sinKernel(r)
        default: return -cosKernel(r)
        }
    }

    public static func cos(_ x: Double) -> Double {
        guard let (r, quadrant) = reduce(x) else { return .nan }
        switch quadrant {
        case 0: return cosKernel(r)
        case 1: return -sinKernel(r)
        case 2: return -cosKernel(r)
        default: return sinKernel(r)
        }
    }

    /// The angle from the positive x axis to (x, y), from -π to π.
    ///
    /// Zero lengths follow C's signs: `atan2(±0, +0)` is ±0, and `atan2(±0, -0)` is ±π.
    public static func atan2(_ y: Double, _ x: Double) -> Double {
        if y.isNaN || x.isNaN { return .nan }
        let up = y.sign == .plus
        if x.isInfinite || y.isInfinite {
            switch (x.isInfinite, y.isInfinite) {
            case (true, true): return (up ? 1 : -1) * (x > 0 ? quarterPi : 3 * quarterPi)
            case (true, false): return x > 0 ? (up ? 0 : -0.0) : (up ? pi : -pi)
            default: return up ? halfPi : -halfPi
            }
        }
        if x == 0 {
            if y == 0 { return x.sign == .plus ? y : (up ? pi : -pi) }
            return up ? halfPi : -halfPi
        }
        let angle = atan(y / x)
        if x > 0 { return angle }
        return up ? angle + pi : angle - pi
    }

    /// The angle whose tangent is `x`, from -π/2 to π/2.
    public static func atan(_ x: Double) -> Double {
        if x.isNaN { return .nan }
        let a = abs(x)
        let angle: Double
        if a > 1 {
            angle = halfPi - atanReduced(1 / a)
        } else {
            angle = atanReduced(a)
        }
        return x.sign == .minus ? -angle : angle
    }

    // MARK: Kernels

    /// `x` as a remainder within ±π/4 of a multiple of π/2, and which quadrant that multiple is,
    /// 0 to 3; `nil` for an infinity or not a number.
    private static func reduce(_ x: Double) -> (Double, Int)? {
        guard x.isFinite else { return nil }
        // Far-off arguments come back within one turn first; the remainder is exact.
        let x = abs(x) > 1_000_000 ? x.truncatingRemainder(dividingBy: twoPi) : x
        let k = (x * twoOverPi).rounded(.toNearestOrEven)
        let r = (x - k * halfPiHead) - k * halfPiTail
        let quadrant = ((Int(k) % 4) + 4) % 4
        return (r, quadrant)
    }

    /// sin(r) for |r| ≤ π/4: its Taylor series to r^17, whose next term is below 1e-18 there.
    private static func sinKernel(_ r: Double) -> Double {
        let r2 = r * r
        var sum = -1.0 / 355_687_428_096_000          // -1/17!
        sum = sum * r2 + 1.0 / 1_307_674_368_000       // 1/15!
        sum = sum * r2 - 1.0 / 6_227_020_800           // -1/13!
        sum = sum * r2 + 1.0 / 39_916_800              // 1/11!
        sum = sum * r2 - 1.0 / 362_880                 // -1/9!
        sum = sum * r2 + 1.0 / 5_040                   // 1/7!
        sum = sum * r2 - 1.0 / 120                     // -1/5!
        sum = sum * r2 + 1.0 / 6                       // 1/3!
        return r - r * r2 * sum
    }

    /// cos(r) for |r| ≤ π/4: its Taylor series to r^18.
    private static func cosKernel(_ r: Double) -> Double {
        let r2 = r * r
        var sum = -1.0 / 6_402_373_705_728_000        // -1/18!
        sum = sum * r2 + 1.0 / 20_922_789_888_000      // 1/16!
        sum = sum * r2 - 1.0 / 87_178_291_200          // -1/14!
        sum = sum * r2 + 1.0 / 479_001_600             // 1/12!
        sum = sum * r2 - 1.0 / 3_628_800               // -1/10!
        sum = sum * r2 + 1.0 / 40_320                  // 1/8!
        sum = sum * r2 - 1.0 / 720                     // -1/6!
        sum = sum * r2 + 1.0 / 24                      // 1/4!
        sum = sum * r2 - 1.0 / 2                       // -1/2!
        return 1 + r2 * sum
    }

    /// atan(a) for 0 ≤ a ≤ 1: around 1 through π/4 + atan((a - 1) / (a + 1)), so the series only
    /// meets |t| ≤ tan(π/8).
    private static func atanReduced(_ a: Double) -> Double {
        guard a > tanEighthPi else { return atanSeries(a) }
        return quarterPi + atanSeries((a - 1) / (a + 1))
    }

    /// atan(t) for |t| ≤ tan(π/8): t - t³/3 + t⁵/5 - …, to t^41, whose next term is below 1e-17.
    private static func atanSeries(_ t: Double) -> Double {
        let t2 = t * t
        var sum = 0.0
        var n = 41.0
        var sign = 1.0   // the t^41 term is positive
        while n >= 3 {
            sum = sum * t2 + sign / n
            sign = -sign
            n -= 2
        }
        return t + t * t2 * sum
    }
}
