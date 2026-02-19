import CoreGraphics
import Foundation
import Vision

// MARK: - TextObservation

/// A recognized text region from OCR.
public struct TextObservation: Sendable {
  /// Recognized text string.
  public let text: String
  /// Recognition confidence (0.0–1.0). Note: 0.5 often means "correct but not
  /// dictionary-validated" in Vision.framework — not necessarily low quality.
  public let confidence: Float
  /// Bounding box in **normalized** coordinates (0.0–1.0), origin bottom-left
  /// (Vision.framework convention).
  public let boundingBox: CGRect

  /// Convert the normalized bounding box to pixel coordinates (origin top-left).
  public func screenRect(imageWidth: CGFloat, imageHeight: CGFloat) -> CGRect {
    CGRect(
      x: boundingBox.origin.x * imageWidth,
      y: (1.0 - boundingBox.origin.y - boundingBox.height) * imageHeight,
      width: boundingBox.width * imageWidth,
      height: boundingBox.height * imageHeight
    )
  }
}

// MARK: - RecognitionMode

/// OCR speed/accuracy trade-off.
public enum RecognitionMode: Sendable {
  /// ~120 ms on M4 for full screen. Supports 6 languages.
  case fast
  /// ~350 ms on M4 for full screen. Supports 18 languages. Better for unusual text.
  case accurate
}

// MARK: - OCREngine

/// Text recognition powered by Apple Vision.framework.
///
/// Stateless — all methods are static. The first call in a process incurs a ~2×
/// cold-start penalty while Vision loads its model.
public struct OCREngine: Sendable {

  /// Recognize text in a `CGImage`.
  ///
  /// - Parameters:
  ///   - image: Source image (screenshot, file, etc.).
  ///   - mode: Speed vs accuracy. Default `.fast` (~120 ms, sufficient for UI text).
  ///   - languages: Recognition language hints. Default `["en-US"]`.
  ///   - languageCorrection: Apply language model correction. Default `true`.
  /// - Returns: Array of ``TextObservation`` sorted top-to-bottom, left-to-right.
  public static func recognizeText(
    in image: CGImage,
    mode: RecognitionMode = .fast,
    languages: [String] = ["en-US"],
    languageCorrection: Bool = true
  ) throws -> [TextObservation] {
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = (mode == .fast) ? .fast : .accurate
    request.usesLanguageCorrection = languageCorrection
    request.recognitionLanguages = languages

    try handler.perform([request])

    let observations = (request.results ?? []).compactMap { obs -> TextObservation? in
      guard let candidate = obs.topCandidates(1).first else { return nil }
      return TextObservation(
        text: candidate.string,
        confidence: candidate.confidence,
        boundingBox: obs.boundingBox
      )
    }

    // Sort top-to-bottom (descending Y in Vision coords), then left-to-right.
    return observations.sorted { a, b in
      let ay = a.boundingBox.origin.y + a.boundingBox.height
      let by = b.boundingBox.origin.y + b.boundingBox.height
      if abs(ay - by) > 0.01 { return ay > by }
      return a.boundingBox.origin.x < b.boundingBox.origin.x
    }
  }

  /// Supported recognition languages for the given mode.
  public static func supportedLanguages(mode: RecognitionMode = .accurate) throws -> [String] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = (mode == .fast) ? .fast : .accurate
    return try request.supportedRecognitionLanguages()
  }
}
