import SwiftUI

/// Semantic haptic events. A view names *what happened*, never a haptic style — see
/// docs/DESIGN_SYSTEM.md §7.
///
/// Deliberately absent: any event for a token, a scroll, a progress update, a tool call, or
/// a stream starting or stopping. Haptics mark state changes the user caused. Everything
/// else is noise, and noise is what makes an app feel cheap.
enum HapticEvent: Equatable {
    case selection
    case reasoningDetent
    case messageSent
    case sidebarThreshold
    case menuOpened
    case toggle
    case taskCompleted
    case buildPassed
    case buildFailed
    case confirmationNeeded
    case modelLoaded
    case destructiveArmed

    var feedback: SensoryFeedback {
        switch self {
        case .selection, .reasoningDetent, .toggle:
            return .selection
        case .messageSent:
            return .impact(weight: .light, intensity: 0.7)
        case .sidebarThreshold:
            return .impact(flexibility: .soft, intensity: 0.5)
        case .menuOpened:
            return .impact(flexibility: .soft, intensity: 0.6)
        case .taskCompleted, .buildPassed:
            return .success
        case .buildFailed:
            return .error
        case .confirmationNeeded:
            return .warning
        case .modelLoaded:
            return .impact(weight: .light, intensity: 0.4)
        case .destructiveArmed:
            return .impact(flexibility: .rigid, intensity: 0.8)
        }
    }
}

extension View {
    /// Fires a semantic haptic when `trigger` changes.
    ///
    /// Uses SwiftUI's `sensoryFeedback`, which respects the system haptic setting and
    /// degrades correctly on devices without a Taptic Engine — both of which hand-rolled
    /// Core Haptics has to reimplement.
    func haptic<V: Equatable>(_ event: HapticEvent, trigger: V) -> some View {
        sensoryFeedback(event.feedback, trigger: trigger)
    }
}

/// Latches a threshold crossing so a gesture that wobbles across it fires once, not
/// repeatedly. Without this the sidebar chatters as your thumb hovers near the midpoint.
@Observable
final class ThresholdLatch {
    private(set) var crossings: Int = 0
    private var isPast = false

    func update(isPast newValue: Bool) {
        guard newValue != isPast else { return }
        isPast = newValue
        crossings += 1
    }

    func reset(isPast newValue: Bool) {
        isPast = newValue
    }
}
