import CoreGraphics
import Foundation

/// Calculates realistic movement timing based on Fitts's Law
public struct FittsLawCalculator: Sendable {

  /// Calculate realistic movement time based on Fitts's Law
  /// T = a + b × log₂(2D/W)
  /// - Parameters:
  ///   - distance: Distance to target in pixels
  ///   - targetWidth: Target width/size in pixels (default 10)
  ///   - a: Fitts's Law intercept constant (default 0.05)
  ///   - b: Fitts's Law slope constant (default 0.15)
  /// - Returns: Movement time in seconds with ±10% jitter
  public static func movementTime(
    distance: CGFloat,
    targetWidth: CGFloat = 10.0,
    a: CGFloat = 0.05,
    b: CGFloat = 0.15
  ) -> TimeInterval {
    // Clamp to avoid log of zero/negative
    let d = max(distance, 1.0)
    let w = max(targetWidth, 1.0)

    // Fitts's Law: T = a + b × log₂(2D/W)
    let indexOfDifficulty = log2(2.0 * d / w)
    let baseTime = a + b * indexOfDifficulty

    // Add ±10% random jitter for realism
    let jitter = CGFloat.random(in: -0.1...0.1)
    let finalTime = baseTime * (1.0 + jitter)

    // Ensure minimum movement time
    return max(TimeInterval(finalTime), 0.02)
  }
}
