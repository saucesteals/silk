import AppKit
import Foundation

/// Unified app name matching across all Silk modules.
///
/// Match strategy (in priority order):
/// 1. Exact match (case-sensitive)
/// 2. Case-insensitive match
/// 3. Case-insensitive prefix match
/// 4. Case-insensitive substring (contains) match
///
/// Only considers apps with `.regular` activation policy (visible dock apps).
public enum AppResolver {

  /// Find a running application by name using the unified matching strategy.
  public static func findApp(named query: String) -> NSRunningApplication? {
    let candidates = NSWorkspace.shared.runningApplications
      .filter { $0.activationPolicy == .regular }

    // 1. Exact match
    if let app = candidates.first(where: { $0.localizedName == query }) {
      return app
    }

    let lowerQuery = query.lowercased()

    // 2. Case-insensitive exact match
    if let app = candidates.first(where: { $0.localizedName?.lowercased() == lowerQuery }) {
      return app
    }

    // 3. Case-insensitive prefix match
    if let app = candidates.first(where: {
      $0.localizedName?.lowercased().hasPrefix(lowerQuery) == true
    }) {
      return app
    }

    // 4. Case-insensitive substring match
    if let app = candidates.first(where: {
      $0.localizedName?.lowercased().contains(lowerQuery) == true
    }) {
      return app
    }

    return nil
  }

  /// Find all running applications matching the query (same strategy, returns all matches at the best tier).
  public static func findApps(named query: String) -> [NSRunningApplication] {
    let candidates = NSWorkspace.shared.runningApplications
      .filter { $0.activationPolicy == .regular }

    // 1. Exact match
    let exact = candidates.filter { $0.localizedName == query }
    if !exact.isEmpty { return exact }

    let lowerQuery = query.lowercased()

    // 2. Case-insensitive exact
    let ciExact = candidates.filter { $0.localizedName?.lowercased() == lowerQuery }
    if !ciExact.isEmpty { return ciExact }

    // 3. Case-insensitive prefix
    let prefix = candidates.filter { $0.localizedName?.lowercased().hasPrefix(lowerQuery) == true }
    if !prefix.isEmpty { return prefix }

    // 4. Case-insensitive substring
    let substring = candidates.filter {
      $0.localizedName?.lowercased().contains(lowerQuery) == true
    }
    return substring
  }
}
