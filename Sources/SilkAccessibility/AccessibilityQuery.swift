// AccessibilityQuery.swift - High-level search API
// Combines tree traversal with query matching for ergonomic element discovery.

import ApplicationServices
import CoreGraphics
import Foundation
import SilkCore

/// High-level accessibility query engine.
/// Searches across one or all applications for matching UI elements.
public enum AccessibilityQuery {

  /// Find elements matching a query.
  /// If `query.application` is set, searches only that app. Otherwise searches all apps.
  public static func find(_ query: ElementQuery) -> SearchResult {
    SilkLogger.ax.debug(
      "Starting query: text=\(query.text ?? "nil") role=\(query.role ?? "nil") app=\(query.application ?? "all")"
    )
    let start = DispatchTime.now()
    var totalSearched = 0
    var results: [Element] = []
    let limit = query.limit > 0 ? query.limit : Int.max

    let appElements: [(String, AXUIElement)]
    if let appName = query.application {
      if let el = AccessibilityTree.applicationElement(named: appName) {
        appElements = [(appName, el)]
      } else {
        SilkLogger.ax.error("Application not found: \(appName)")
        return SearchResult(elements: [], durationMs: 0, searchedCount: 0)
      }
    } else {
      appElements = AccessibilityTree.allApplicationElements()
    }

    for (_, appElement) in appElements {
      if results.count >= limit { break }

      var visited = Set<UInt>()
      totalSearched += AccessibilityTree.traverse(
        appElement,
        maxDepth: query.maxDepth,
        visited: &visited
      ) { element in
        guard results.count < limit else { return false }
        if elementMatchesQuery(element, query) {
          results.append(element)
        }
        return results.count < limit  // stop recursing if we hit limit
      }
    }

    // Phase 3: Compute visibility for each result
    let visibilityData = computeVisibilityBatch(for: results)
    for i in results.indices {
      results[i].visibility = visibilityData[i].0
      results[i].scrollContainer = visibilityData[i].1
    }

    let elapsed = Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
    SilkLogger.ax.info(
      "Query complete: found \(results.count) elements in \(elapsed)ms (searched \(totalSearched) nodes)"
    )
    return SearchResult(elements: results, durationMs: elapsed, searchedCount: totalSearched)
  }

  /// Find the element at a screen coordinate.
  public static func elementAt(x: CGFloat, y: CGFloat) -> Element? {
    SilkLogger.ax.debug("Finding element at position: (\(x), \(y))")
    let result = AccessibilityTree.elementAtPosition(x: Float(x), y: Float(y))
    if result != nil {
      SilkLogger.ax.debug("Found element at (\(x), \(y)): \(result!.role)")
    } else {
      SilkLogger.ax.debug("No element found at (\(x), \(y))")
    }
    return result
  }

  /// Get all elements for an application up to a given depth.
  public static func getAllElements(application: String, depth: Int = 100) -> [Element] {
    guard let appElement = AccessibilityTree.applicationElement(named: application) else {
      return []
    }
    return AccessibilityTree.collectElements(from: appElement, maxDepth: depth)
  }

  /// Find elements by text across all apps (convenience).
  public static func findByText(_ text: String, role: String? = nil, limit: Int = 10) -> [Element] {
    find(ElementQuery(text: text, role: role, fuzzyMatch: true, limit: limit)).elements
  }

  /// Find elements by role in a specific app (convenience).
  public static func findByRole(_ role: String, in app: String, limit: Int = 50) -> [Element] {
    find(ElementQuery(role: role, application: app, limit: limit)).elements
  }

  /// Perform an action on an AXUIElement (e.g. AXPress for clicking).
  public static func performAction(_ action: String, on element: AXUIElement) -> Bool {
    let result = AXUIElementPerformAction(element, action as CFString)
    SilkLogger.logAXCall("AXUIElementPerformAction", attribute: action, result: result)
    return result == .success
  }

  /// Press (click) an element.
  @discardableResult
  public static func press(_ element: Element) -> Bool {
    performAction(kAXPressAction as String, on: element.axElement)
  }
}
