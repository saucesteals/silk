import AppKit
import CoreGraphics

/// Visual overlay that draws a fading trail behind the cursor during humanized movement
/// @unchecked because mutable state (window, trailView) is only accessed
/// via DispatchQueue.main.async, ensuring serial access on the main thread.
public final class TrailOverlay: @unchecked Sendable {
  private var window: NSWindow?
  private var trailView: TrailView?
  private let duration: TimeInterval
  private let color: NSColor

  public init(duration: TimeInterval = 3.0, color: NSColor = .cyan) {
    self.duration = duration
    self.color = color
  }

  /// Show the overlay window
  public func show() {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      guard let screen = NSScreen.main else { return }

      let window = NSWindow(
        contentRect: screen.frame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
      )
      window.level = .floating  // Above normal windows, but visible in screen sharing
      window.backgroundColor = .clear
      window.isOpaque = false
      window.hasShadow = false
      window.ignoresMouseEvents = true
      window.collectionBehavior = [.canJoinAllSpaces, .stationary]

      let trailView = TrailView(frame: screen.frame, color: self.color, duration: self.duration)
      window.contentView = trailView
      window.orderFrontRegardless()

      self.window = window
      self.trailView = trailView
    }
  }

  /// Hide and clean up the overlay
  public func hide() {
    DispatchQueue.main.async { [weak self] in
      self?.window?.close()
      self?.window = nil
      self?.trailView = nil
    }
  }

  /// Add a point to the trail
  public func addPoint(_ point: CGPoint) {
    DispatchQueue.main.async { [weak self] in
      self?.trailView?.addPoint(point)
    }
  }

  /// Mark the trail as complete (start fade-out timer)
  public func complete() {
    DispatchQueue.main.async { [weak self] in
      self?.trailView?.complete()
    }
  }
}

/// Custom view that renders the trail with fade-out animation
@MainActor
private final class TrailView: NSView {
  private var points: [CGPoint] = []
  private var isComplete = false
  private var fadeTimer: Timer?
  private var fadeProgress: CGFloat = 0.0
  private let color: NSColor
  private let duration: TimeInterval

  init(frame: NSRect, color: NSColor, duration: TimeInterval) {
    self.color = color
    self.duration = duration
    super.init(frame: frame)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) not implemented")
  }

  func addPoint(_ point: CGPoint) {
    points.append(point)
    needsDisplay = true
  }

  func complete() {
    isComplete = true

    // Start fade-out animation (Timer.scheduledTimer runs on main thread by default)
    fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
      guard let self = self else {
        timer.invalidate()
        return
      }

      // Timer runs on main RunLoop - safe to assume main actor isolation
      let shouldStop = MainActor.assumeIsolated {
        // Update fade progress (now properly synchronized via @MainActor)
        self.fadeProgress += 0.05 / self.duration

        // Trigger redraw (already on main thread)
        self.needsDisplay = true

        // Return completion flag
        return self.fadeProgress >= 1.0
      }

      // Handle timer invalidation outside the actor context
      if shouldStop {
        timer.invalidate()
        // Close window after fade completes
        Task { @MainActor in
          try? await Task.sleep(nanoseconds: 100_000_000)
          self.window?.close()
        }
      }
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    guard let context = NSGraphicsContext.current?.cgContext else { return }
    guard points.count >= 2 else { return }

    // Calculate opacity based on fade progress
    let opacity = isComplete ? 1.0 - fadeProgress : 1.0

    // Draw the trail
    context.setLineWidth(3.0)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setStrokeColor(color.withAlphaComponent(opacity).cgColor)

    // Convert from CG coordinates (top-left origin) to AppKit coordinates (bottom-left origin)
    let screenHeight = bounds.height

    context.beginPath()
    let firstPoint = CGPoint(x: points[0].x, y: screenHeight - points[0].y)
    context.move(to: firstPoint)

    for i in 1..<points.count {
      let point = CGPoint(x: points[i].x, y: screenHeight - points[i].y)
      context.addLine(to: point)
    }

    context.strokePath()
  }
}
