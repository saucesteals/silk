import Foundation

/// Menu click options
public struct MenuClickOptions: Sendable {
  public let app: String?  // nil = menu bar app
  public let menuPath: [String]  // e.g., ["File", "New Window"]

  public init(app: String? = nil, menuPath: [String]) {
    self.app = app
    self.menuPath = menuPath
  }
}

/// Menu operation result
public struct MenuResult: Sendable, Encodable {
  public let action: String
  public let appName: String?
  public let menuPath: [String]
  public let success: Bool
  public let durationMs: Int

  enum CodingKeys: String, CodingKey {
    case action
    case appName = "app_name"
    case menuPath = "menu_path"
    case success
    case durationMs = "duration_ms"
  }

  public init(
    action: String,
    appName: String?,
    menuPath: [String],
    success: Bool,
    durationMs: Int
  ) {
    self.action = action
    self.appName = appName
    self.menuPath = menuPath
    self.success = success
    self.durationMs = durationMs
  }
}

/// Menu item info
public struct MenuItem: Sendable, Encodable {
  public let title: String
  public let enabled: Bool
  public let hasSubmenu: Bool
  public let shortcut: String?

  enum CodingKeys: String, CodingKey {
    case title, enabled
    case hasSubmenu = "has_submenu"
    case shortcut
  }

  public init(title: String, enabled: Bool, hasSubmenu: Bool, shortcut: String?) {
    self.title = title
    self.enabled = enabled
    self.hasSubmenu = hasSubmenu
    self.shortcut = shortcut
  }
}

/// Dock click options
public struct DockClickOptions: Sendable {
  public let appName: String
  public let rightClick: Bool  // Show context menu

  public init(appName: String, rightClick: Bool = false) {
    self.appName = appName
    self.rightClick = rightClick
  }
}

/// Dock operation result
public struct DockResult: Sendable, Encodable {
  public let action: String
  public let appName: String
  public let success: Bool
  public let durationMs: Int

  enum CodingKeys: String, CodingKey {
    case action
    case appName = "app_name"
    case success
    case durationMs = "duration_ms"
  }

  public init(
    action: String,
    appName: String,
    success: Bool,
    durationMs: Int
  ) {
    self.action = action
    self.appName = appName
    self.success = success
    self.durationMs = durationMs
  }
}

/// Dock app info
public struct DockApp: Sendable, Encodable {
  public let name: String
  public let bundleId: String
  public let isRunning: Bool

  enum CodingKeys: String, CodingKey {
    case name
    case bundleId = "bundle_id"
    case isRunning = "is_running"
  }

  public init(name: String, bundleId: String, isRunning: Bool) {
    self.name = name
    self.bundleId = bundleId
    self.isRunning = isRunning
  }
}
