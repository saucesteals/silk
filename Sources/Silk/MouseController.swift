import AppKit
import CoreGraphics
import Foundation
import SilkCore
import SilkHumanization

/// High-level mouse control interface
public final class MouseController: Sendable {
  private let eventPoster: EventPoster

  public init(eventPoster: EventPoster = CGEventPoster()) {
    self.eventPoster = eventPoster
  }

  /// Move mouse to specified coordinates
  /// - Parameters:
  ///   - x: X coordinate (in CoreGraphics coordinates: origin top-left)
  ///   - y: Y coordinate (in CoreGraphics coordinates: origin top-left)
  ///   - humanize: Whether to use natural movement
  ///   - showTrail: Whether to draw a visual trail overlay (only with humanize=true)
  ///   - trailDuration: How long the trail stays visible after movement completes
  public func moveTo(
    x: CGFloat, y: CGFloat, humanize: Bool = false, showTrail: Bool = false,
    trailDuration: TimeInterval = 3.0
  ) async throws {
    let target = CGPoint(x: x, y: y)

    if humanize {
      // Get current position (already in CG coordinates: top-left origin)
      let currentPos = getPosition()

      let movement = HumanizedMovement.generateMovement(
        from: currentPos,
        to: target
      )

      // Setup trail overlay if requested
      var trailOverlay: TrailOverlay? = nil
      if showTrail {
        trailOverlay = TrailOverlay(duration: trailDuration)
        trailOverlay?.show()
        // Add starting point
        trailOverlay?.addPoint(currentPos)
        // Give the window time to appear
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
      }

      for step in movement {
        try eventPoster.postMouseMove(to: step.point)
        trailOverlay?.addPoint(step.point)
        try await Task.sleep(nanoseconds: UInt64(step.delay * 1_000_000_000))
      }

      // Mark trail as complete (start fade-out)
      trailOverlay?.complete()
    } else {
      // Direct teleport
      try eventPoster.postMouseMove(to: target)
    }
  }

  /// Click at specified coordinates
  /// - Parameters:
  ///   - x: X coordinate
  ///   - y: Y coordinate
  ///   - button: Mouse button to click
  ///   - variance: Random offset in pixels (0 = exact position)
  public func click(
    x: CGFloat,
    y: CGFloat,
    button: MouseButton = .left,
    variance: CGFloat = 0
  ) async throws {
    // Apply coordinate variance
    let actualX = x + CGFloat.random(in: -variance...variance)
    let actualY = y + CGFloat.random(in: -variance...variance)
    let point = CGPoint(x: actualX, y: actualY)

    // Move to position first
    try eventPoster.postMouseMove(to: point)

    // Natural click duration (50-150ms)
    let clickDuration = Double.random(in: 0.05...0.15)

    // Press
    try eventPoster.postMouseButton(button, down: true, at: point)

    // Hold
    try await Task.sleep(nanoseconds: UInt64(clickDuration * 1_000_000_000))

    // Release
    try eventPoster.postMouseButton(button, down: false, at: point)
  }

  /// Get current mouse position (in CoreGraphics coordinates: origin top-left)
  public func getPosition() -> CGPoint {
    let appKitLocation = NSEvent.mouseLocation
    return CoordinateSystem.appKitToCG(appKitLocation)
  }

  /// Scroll by specified delta
  /// - Parameters:
  ///   - deltaY: Vertical scroll amount (positive = down, negative = up)
  ///   - deltaX: Horizontal scroll amount (positive = right, negative = left)
  public func scroll(deltaY: Int32, deltaX: Int32 = 0) throws {
    try eventPoster.postScroll(deltaY: deltaY, deltaX: deltaX)
  }
}
