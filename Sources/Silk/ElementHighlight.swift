// ElementHighlight.swift - Draw bounding boxes around UI elements for debugging

import AppKit
import CoreGraphics
import SilkCore

@MainActor
public class ElementHighlight {
  private static var windows: [NSWindow] = []

  /// Highlight an element with a colored bounding box
  public static func highlight(
    frame: CGRect,
    color: NSColor = .systemGreen,
    duration: TimeInterval = 3.0,
    label: String? = nil
  ) {
    DispatchQueue.main.async {
      // Convert from Accessibility API coordinates (CG/top-left origin) to AppKit/screen coordinates (bottom-left origin)
      // AX APIs use Core Graphics coordinate system (top-left), but NSWindow expects AppKit coordinates (bottom-left)
      let originAppKit = CoordinateSystem.cgToAppKit(frame.origin)
      let screenFrame = CGRect(
        x: originAppKit.x,
        y: originAppKit.y - frame.size.height,  // Adjust for frame height since origin is top-left in CG but bottom-left in AppKit
        width: frame.size.width,
        height: frame.size.height
      )

      // Create overlay window
      let window = NSWindow(
        contentRect: screenFrame,
        styleMask: .borderless,
        backing: .buffered,
        defer: false
      )

      window.backgroundColor = .clear
      window.isOpaque = false
      window.level = .floating
      window.ignoresMouseEvents = true
      window.collectionBehavior = [.canJoinAllSpaces, .stationary]

      // Create border view
      let borderView = BorderView(frame: CGRect(origin: .zero, size: frame.size))
      borderView.borderColor = color
      borderView.label = label
      window.contentView = borderView

      window.orderFrontRegardless()
      windows.append(window)

      // Auto-hide after duration
      DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
        window.orderOut(nil)
        windows.removeAll { $0 == window }
      }
    }
  }

  /// Clear all highlights
  public static func clearAll() {
    DispatchQueue.main.async {
      windows.forEach { $0.orderOut(nil) }
      windows.removeAll()
    }
  }
}

private class BorderView: NSView {
  var borderColor: NSColor = .systemGreen
  var label: String?

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    // Draw border
    let path = NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2))
    path.lineWidth = 4
    borderColor.setStroke()
    path.stroke()

    // Draw label if present
    if let label = label {
      let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .bold),
        .foregroundColor: NSColor.white,
        .backgroundColor: borderColor,
      ]

      let attrString = NSAttributedString(string: " \(label) ", attributes: attrs)
      let size = attrString.size()
      let labelRect = CGRect(
        x: 4,
        y: bounds.height - size.height - 4,
        width: size.width,
        height: size.height
      )

      attrString.draw(in: labelRect)
    }
  }
}
