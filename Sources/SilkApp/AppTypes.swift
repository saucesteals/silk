import Foundation

/// App launch options
public struct LaunchOptions: Sendable {
  public let appName: String
  public let openURL: String?  // Optional URL/file to open
  public let hidden: Bool  // Launch hidden
  public let activate: Bool  // Bring to front

  public init(
    appName: String,
    openURL: String? = nil,
    hidden: Bool = false,
    activate: Bool = true
  ) {
    self.appName = appName
    self.openURL = openURL
    self.hidden = hidden
    self.activate = activate
  }
}

/// App quit options
public struct QuitOptions: Sendable {
  public let appName: String
  public let force: Bool  // Force quit (SIGKILL)

  public init(appName: String, force: Bool = false) {
    self.appName = appName
    self.force = force
  }
}

/// App hide options
public struct HideOptions: Sendable {
  public let appName: String

  public init(appName: String) {
    self.appName = appName
  }
}

/// App switch options
public struct SwitchOptions: Sendable {
  public let appName: String

  public init(appName: String) {
    self.appName = appName
  }
}

/// App operation result
public struct AppResult: Sendable, Encodable {
  public let action: String
  public let appName: String
  public let success: Bool
  public let pid: Int?  // Process ID (for launch/switch)
  public let bundleId: String?
  public let durationMs: Int

  enum CodingKeys: String, CodingKey {
    case action
    case appName = "app_name"
    case success, pid
    case bundleId = "bundle_id"
    case durationMs = "duration_ms"
  }

  public init(
    action: String,
    appName: String,
    success: Bool,
    pid: Int? = nil,
    bundleId: String? = nil,
    durationMs: Int
  ) {
    self.action = action
    self.appName = appName
    self.success = success
    self.pid = pid
    self.bundleId = bundleId
    self.durationMs = durationMs
  }
}

/// App info (for list command)
public struct AppInfo: Sendable, Encodable {
  public let name: String
  public let bundleId: String
  public let pid: Int
  public let isActive: Bool
  public let isHidden: Bool

  enum CodingKeys: String, CodingKey {
    case name
    case bundleId = "bundle_id"
    case pid
    case isActive = "is_active"
    case isHidden = "is_hidden"
  }

  public init(
    name: String,
    bundleId: String,
    pid: Int,
    isActive: Bool,
    isHidden: Bool
  ) {
    self.name = name
    self.bundleId = bundleId
    self.pid = pid
    self.isActive = isActive
    self.isHidden = isHidden
  }
}
