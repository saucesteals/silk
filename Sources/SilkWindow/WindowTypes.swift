import CoreGraphics
import Foundation

/// Window identification
public struct WindowIdentifier: Sendable {
  public let app: String?
  public let title: String?
  public let index: Int?  // 0 = frontmost window

  public init(app: String? = nil, title: String? = nil, index: Int? = nil) {
    self.app = app
    self.title = title
    self.index = index
  }
}

/// Window move options
public struct WindowMoveOptions: Sendable {
  public let identifier: WindowIdentifier
  public let x: Int
  public let y: Int

  public init(identifier: WindowIdentifier, x: Int, y: Int) {
    self.identifier = identifier
    self.x = x
    self.y = y
  }
}

/// Window resize options
public struct WindowResizeOptions: Sendable {
  public let identifier: WindowIdentifier
  public let width: Int
  public let height: Int

  public init(identifier: WindowIdentifier, width: Int, height: Int) {
    self.identifier = identifier
    self.width = width
    self.height = height
  }
}

/// Window close options
public struct WindowCloseOptions: Sendable {
  public let identifier: WindowIdentifier

  public init(identifier: WindowIdentifier) {
    self.identifier = identifier
  }
}

/// Window state
public enum WindowState: String, Sendable {
  case minimize
  case maximize
  case restore
  case fullscreen
}

/// Window minimize/maximize options
public struct WindowStateOptions: Sendable {
  public let identifier: WindowIdentifier
  public let state: WindowState

  public init(identifier: WindowIdentifier, state: WindowState) {
    self.identifier = identifier
    self.state = state
  }
}

/// Window operation result
public struct WindowResult: Sendable, Encodable {
  public let action: String
  public let appName: String
  public let windowTitle: String?
  public let success: Bool
  public let x: Int?
  public let y: Int?
  public let width: Int?
  public let height: Int?
  public let durationMs: Int

  enum CodingKeys: String, CodingKey {
    case action
    case appName = "app_name"
    case windowTitle = "window_title"
    case success, x, y, width, height
    case durationMs = "duration_ms"
  }

  public init(
    action: String,
    appName: String,
    windowTitle: String? = nil,
    success: Bool,
    x: Int? = nil,
    y: Int? = nil,
    width: Int? = nil,
    height: Int? = nil,
    durationMs: Int
  ) {
    self.action = action
    self.appName = appName
    self.windowTitle = windowTitle
    self.success = success
    self.x = x
    self.y = y
    self.width = width
    self.height = height
    self.durationMs = durationMs
  }
}

/// Window info (for list command)
public struct WindowInfo: Sendable, Encodable {
  public let appName: String
  public let title: String
  public let x: Int
  public let y: Int
  public let width: Int
  public let height: Int
  public let isMinimized: Bool
  public let isFullscreen: Bool

  enum CodingKeys: String, CodingKey {
    case appName = "app_name"
    case title, x, y, width, height
    case isMinimized = "is_minimized"
    case isFullscreen = "is_fullscreen"
  }

  public init(
    appName: String,
    title: String,
    x: Int,
    y: Int,
    width: Int,
    height: Int,
    isMinimized: Bool,
    isFullscreen: Bool
  ) {
    self.appName = appName
    self.title = title
    self.x = x
    self.y = y
    self.width = width
    self.height = height
    self.isMinimized = isMinimized
    self.isFullscreen = isFullscreen
  }
}
