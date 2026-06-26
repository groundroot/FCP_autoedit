import Foundation
import SwiftUI

/// Manages free vs PRO status. Phase 3 placeholder — real StoreKit purchase added later.
/// Free tier: all features available, but export is capped at 60 seconds of kept content.
@MainActor
@Observable
final class ProManager {

    static let freeLimitSeconds: Double = 60.0

    private(set) var isPro: Bool = false

    init() {
        isPro = UserDefaults.standard.bool(forKey: "proUnlocked")
    }

    /// Unlock PRO (called from StoreKit purchase completion — placeholder).
    func unlock() {
        isPro = true
        UserDefaults.standard.set(true, forKey: "proUnlocked")
    }

    /// Revoke PRO (for testing / refund handling).
    func revoke() {
        isPro = false
        UserDefaults.standard.set(false, forKey: "proUnlocked")
    }

    /// Returns the subset of segments that fit within the free limit.
    /// For PRO users, returns all kept segments unchanged.
    func clampedSegments(_ segments: [Segment]) -> (segments: [Segment], wasClamped: Bool) {
        guard !isPro else { return (segments, false) }

        var total: Double = 0
        var result: [Segment] = []

        for seg in segments {
            guard seg.isKept else {
                result.append(seg)
                continue
            }
            let dur = seg.end - seg.start
            if total + dur <= Self.freeLimitSeconds {
                result.append(seg)
                total += dur
            } else {
                // Partially include up to the limit
                let remaining = Self.freeLimitSeconds - total
                if remaining > 0.1 {
                    var partial = seg
                    partial.end = seg.start + remaining
                    result.append(partial)
                    total += remaining
                }
                break
            }
        }

        let wasClamped = result.filter(\.isKept).count < segments.filter(\.isKept).count
            || (result.last?.end != segments.last?.end && !result.isEmpty)

        return (result, wasClamped)
    }

    /// Total kept duration in seconds for the given segments.
    static func keptDuration(_ segments: [Segment]) -> Double {
        segments.filter(\.isKept).reduce(0) { $0 + $1.end - $1.start }
    }
}
