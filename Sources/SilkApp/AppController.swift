import AppKit
import Foundation

public enum AppError: Error, LocalizedError {
  case appNotFound(String)
  case appNotRunning(String)
  case launchFailed(String, String)
  case quitFailed(String, String)
  case hideFailed(String)
  case switchFailed(String)

  public var errorDescription: String? {
    switch self {
    case .appNotFound(let name):
      return "Application not found: \(name)"
    case .appNotRunning(let name):
      return "Application not running: \(name)"
    case .launchFailed(let name, let reason):
      return "Failed to launch \(name): \(reason)"
    case .quitFailed(let name, let reason):
      return "Failed to quit \(name): \(reason)"
    case .hideFailed(let name):
      return "Failed to hide \(name)"
    case .switchFailed(let name):
      return "Failed to switch to \(name)"
    }
  }
}

public final class AppController: Sendable {

  public init() {}

  // MARK: - Public API

  /// Launch an application
  public func launch(_ options: LaunchOptions) async throws -> AppResult {
    let start = DispatchTime.now()

    // Check if already running
    if let running = findRunningApp(named: options.appName) {
      // Already running - handle URL/activate
      if let urlString = options.openURL {
        try await openURL(urlString, with: running)
      }
      if options.activate && !options.hidden {
        running.activate()
      }
      if options.hidden {
        running.hide()
      }
      let ms = millisSince(start)
      return AppResult(
        action: "launch",
        appName: running.localizedName ?? options.appName,
        success: true,
        pid: Int(running.processIdentifier),
        bundleId: running.bundleIdentifier,
        durationMs: ms
      )
    }

    // Find app bundle URL
    guard let appURL = findAppURL(named: options.appName) else {
      throw AppError.appNotFound(options.appName)
    }

    // Build launch configuration
    let config = NSWorkspace.OpenConfiguration()
    config.activates = options.activate && !options.hidden
    config.hides = options.hidden

    // If we have a URL to open, open it with this app
    if let urlString = options.openURL {
      let targetURL: URL
      if urlString.hasPrefix("http://") || urlString.hasPrefix("https://")
        || urlString.hasPrefix("file://")
      {
        guard let url = URL(string: urlString) else {
          throw AppError.launchFailed(options.appName, "Invalid URL: \(urlString)")
        }
        targetURL = url
      } else {
        // Treat as file path
        targetURL = URL(fileURLWithPath: (urlString as NSString).expandingTildeInPath)
      }

      let app = try await NSWorkspace.shared.open(
        [targetURL],
        withApplicationAt: appURL,
        configuration: config
      )

      let ms = millisSince(start)
      return AppResult(
        action: "launch",
        appName: app.localizedName ?? options.appName,
        success: true,
        pid: Int(app.processIdentifier),
        bundleId: app.bundleIdentifier,
        durationMs: ms
      )
    } else {
      // Just launch the app
      let app = try await NSWorkspace.shared.openApplication(
        at: appURL,
        configuration: config
      )

      let ms = millisSince(start)
      return AppResult(
        action: "launch",
        appName: app.localizedName ?? options.appName,
        success: true,
        pid: Int(app.processIdentifier),
        bundleId: app.bundleIdentifier,
        durationMs: ms
      )
    }
  }

  /// Quit an application
  public func quit(_ options: QuitOptions) async throws -> AppResult {
    let start = DispatchTime.now()

    guard let app = findRunningApp(named: options.appName) else {
      throw AppError.appNotRunning(options.appName)
    }

    let appName = app.localizedName ?? options.appName
    let bundleId = app.bundleIdentifier
    let pid = Int(app.processIdentifier)

    if options.force {
      // Force quit via SIGKILL
      app.forceTerminate()
    } else {
      // Graceful quit
      app.terminate()
    }

    // Wait for app to quit (up to 5 seconds) by checking if process exists
    let deadline = Date().addingTimeInterval(5.0)
    var terminated = false
    while Date() < deadline {
      // Check if process is still alive via kill(0)
      if kill(pid_t(pid), 0) != 0 {
        terminated = true
        break
      }
      try await Task.sleep(for: .milliseconds(100))
    }

    let ms = millisSince(start)
    return AppResult(
      action: options.force ? "force_quit" : "quit",
      appName: appName,
      success: terminated,
      pid: pid,
      bundleId: bundleId,
      durationMs: ms
    )
  }

  /// Hide an application
  public func hide(_ options: HideOptions) throws -> AppResult {
    let start = DispatchTime.now()

    guard let app = findRunningApp(named: options.appName) else {
      throw AppError.appNotRunning(options.appName)
    }

    // NSRunningApplication.hide() return value is unreliable on macOS
    // (often returns false even when the operation succeeds).
    // We send the hide request and trust it worked.
    _ = app.hide()

    let ms = millisSince(start)
    return AppResult(
      action: "hide",
      appName: app.localizedName ?? options.appName,
      success: true,
      pid: Int(app.processIdentifier),
      bundleId: app.bundleIdentifier,
      durationMs: ms
    )
  }

  /// Switch to an application (bring to front)
  public func switchTo(_ options: SwitchOptions) throws -> AppResult {
    let start = DispatchTime.now()

    guard let app = findRunningApp(named: options.appName) else {
      throw AppError.appNotRunning(options.appName)
    }

    // Unhide first if hidden, then activate
    if app.isHidden {
      _ = app.unhide()
    }
    _ = app.activate()

    let ms = millisSince(start)
    return AppResult(
      action: "switch",
      appName: app.localizedName ?? options.appName,
      success: true,
      pid: Int(app.processIdentifier),
      bundleId: app.bundleIdentifier,
      durationMs: ms
    )
  }

  /// List all running applications
  public func listRunning() -> [AppInfo] {
    let workspace = NSWorkspace.shared
    let frontmost = workspace.frontmostApplication

    return workspace.runningApplications
      .filter { $0.activationPolicy == .regular }
      .compactMap { app -> AppInfo? in
        guard let name = app.localizedName,
          let bundleId = app.bundleIdentifier
        else {
          return nil
        }
        return AppInfo(
          name: name,
          bundleId: bundleId,
          pid: Int(app.processIdentifier),
          isActive: app.processIdentifier == frontmost?.processIdentifier,
          isHidden: app.isHidden
        )
      }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  // MARK: - Private Helpers

  /// Find a running application by name (case-insensitive)
  private func findRunningApp(named name: String) -> NSRunningApplication? {
    let lowerName = name.lowercased()
    return NSWorkspace.shared.runningApplications
      .filter { $0.activationPolicy == .regular }
      .first { app in
        if let localName = app.localizedName?.lowercased() {
          return localName == lowerName || localName.hasPrefix(lowerName)
        }
        return false
      }
  }

  /// Find an application URL by name
  private func findAppURL(named name: String) -> URL? {
    // Try exact name with .app extension
    let appName = name.hasSuffix(".app") ? name : "\(name).app"

    // Search common locations
    let searchPaths = [
      "/Applications",
      "/Applications/Utilities",
      "/System/Applications",
      "/System/Applications/Utilities",
      NSHomeDirectory() + "/Applications",
    ]

    for path in searchPaths {
      let fullPath = "\(path)/\(appName)"
      if FileManager.default.fileExists(atPath: fullPath) {
        return URL(fileURLWithPath: fullPath)
      }
    }

    // Try Spotlight / Launch Services
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) {
      return url
    }

    // Try case-insensitive search in /Applications
    let lowerAppName = appName.lowercased()
    for path in searchPaths {
      if let contents = try? FileManager.default.contentsOfDirectory(atPath: path) {
        for item in contents where item.lowercased() == lowerAppName {
          return URL(fileURLWithPath: "\(path)/\(item)")
        }
      }
    }

    return nil
  }

  /// Open a URL with a specific running application
  private func openURL(_ urlString: String, with app: NSRunningApplication) async throws {
    let url: URL
    if urlString.hasPrefix("http://") || urlString.hasPrefix("https://")
      || urlString.hasPrefix("file://")
    {
      guard let parsed = URL(string: urlString) else {
        throw AppError.launchFailed(app.localizedName ?? "unknown", "Invalid URL: \(urlString)")
      }
      url = parsed
    } else {
      url = URL(fileURLWithPath: (urlString as NSString).expandingTildeInPath)
    }

    let config = NSWorkspace.OpenConfiguration()
    config.activates = true

    guard let appURL = app.bundleURL else {
      throw AppError.launchFailed(app.localizedName ?? "unknown", "No bundle URL")
    }

    do {
      _ = try await NSWorkspace.shared.open(
        [url],
        withApplicationAt: appURL,
        configuration: config
      )
    } catch {
      throw AppError.launchFailed(app.localizedName ?? "unknown", error.localizedDescription)
    }
  }

  private func millisSince(_ start: DispatchTime) -> Int {
    Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
  }
}
