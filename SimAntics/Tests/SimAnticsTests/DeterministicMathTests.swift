import Foundation
import Testing
@testable import SimAntics

/// Routing's `sin`, `cos`, and `atan2`: close to the platform's, exact where they should be, and
/// the same bits every time.
@Suite struct DeterministicMathTests {
    @Test func agreesWithThePlatformToALastBitOrTwo() {
        var x = -40.0
        while x <= 40 {
            #expect(abs(DeterministicMath.sin(x) - Foundation.sin(x)) <= 4e-16, "sin(\(x))")
            #expect(abs(DeterministicMath.cos(x) - Foundation.cos(x)) <= 4e-16, "cos(\(x))")
            x += 0.00731
        }
        for y in stride(from: -200.0, through: 200, by: 1.5) {
            for x in stride(from: -200.0, through: 200, by: 1.25) {
                #expect(abs(DeterministicMath.atan2(y, x) - Foundation.atan2(y, x)) <= 1e-15, "atan2(\(y), \(x))")
            }
        }
    }

    @Test func isExactAtTheAxesAndZero() {
        #expect(DeterministicMath.sin(0) == 0 && DeterministicMath.cos(0) == 1)
        #expect(DeterministicMath.atan2(0, 1) == 0 && DeterministicMath.atan2(1, 0) == DeterministicMath.halfPi)
        #expect(DeterministicMath.atan2(-1, 0) == -DeterministicMath.halfPi && DeterministicMath.atan2(0, -1) == DeterministicMath.pi)
        #expect(DeterministicMath.atan2(-0.0, -1) == -DeterministicMath.pi)
        #expect(DeterministicMath.atan2(1, 1) == DeterministicMath.quarterPi)
        #expect(DeterministicMath.atan2(0, 0) == 0 && DeterministicMath.atan2(-0.0, 0).sign == .minus)
    }

    @Test func handlesWhatIsntANumber() {
        #expect(DeterministicMath.sin(.nan).isNaN && DeterministicMath.cos(.infinity).isNaN)
        #expect(DeterministicMath.atan2(.nan, 1).isNaN)
        #expect(DeterministicMath.atan2(.infinity, 1) == DeterministicMath.halfPi)
        #expect(DeterministicMath.atan2(1, -.infinity) == DeterministicMath.pi)
        #expect(DeterministicMath.sin(3e9).isFinite, "far-off arguments come back within a turn")
    }

    /// The bits themselves, so a change to the math, or a compiler that rounds differently, shows.
    @Test func givesTheSameBitsAsEver() {
        #expect(DeterministicMath.sin(1).bitPattern == 4_605_754_516_372_524_270)
        #expect(DeterministicMath.cos(1).bitPattern == 4_603_041_830_072_026_764)
        #expect(DeterministicMath.atan2(1, 2).bitPattern == 4_602_023_952_714_414_927)
        #expect(DeterministicMath.atan2(-3, -7).bitPattern == 13_836_716_958_157_902_218)
        #expect(DeterministicMath.sin(100).bitPattern == 13_826_108_192_625_282_488)
    }
}
