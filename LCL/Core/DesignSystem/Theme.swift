import SwiftUI
import Observation

/// The user-selectable accent.
///
/// Still one accent at a time — the rule is "a single restrained hue for interactive accents
/// and nothing else" (docs/DESIGN_SYSTEM.md §2), not "one hardcoded hue". Each choice carries
/// a lifted dark-mode variant, because a colour that works on white fails on true black.
enum AccentChoice: String, CaseIterable, Identifiable, Sendable {
    case teal
    case blue
    case indigo
    case amber
    case rose
    case graphite

    var id: String { rawValue }

    var name: String {
        switch self {
        case .teal: return "Teal"
        case .blue: return "Blue"
        case .indigo: return "Indigo"
        case .amber: return "Amber"
        case .rose: return "Rose"
        case .graphite: return "Graphite"
        }
    }

    var color: Color {
        Color(UIColor { [self] traits in
            let dark = traits.userInterfaceStyle == .dark
            switch self {
            case .teal:
                return dark
                    ? UIColor(red: 0.373, green: 0.702, blue: 0.675, alpha: 1)
                    : UIColor(red: 0.184, green: 0.435, blue: 0.420, alpha: 1)
            case .blue:
                return dark
                    ? UIColor(red: 0.400, green: 0.650, blue: 0.960, alpha: 1)
                    : UIColor(red: 0.098, green: 0.396, blue: 0.784, alpha: 1)
            case .indigo:
                return dark
                    ? UIColor(red: 0.639, green: 0.596, blue: 0.965, alpha: 1)
                    : UIColor(red: 0.361, green: 0.310, blue: 0.769, alpha: 1)
            case .amber:
                return dark
                    ? UIColor(red: 0.918, green: 0.694, blue: 0.302, alpha: 1)
                    : UIColor(red: 0.686, green: 0.451, blue: 0.078, alpha: 1)
            case .rose:
                return dark
                    ? UIColor(red: 0.937, green: 0.545, blue: 0.616, alpha: 1)
                    : UIColor(red: 0.729, green: 0.235, blue: 0.322, alpha: 1)
            case .graphite:
                return dark
                    ? UIColor(white: 0.78, alpha: 1)
                    : UIColor(white: 0.28, alpha: 1)
            }
        })
    }
}

/// Persisted app settings. Small on purpose — it grows only as real settings appear.
@Observable
final class AppSettings {
    private enum Key {
        static let accent = "settings.accent"
    }

    var accent: AccentChoice {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: Key.accent) }
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: Key.accent)
        accent = stored.flatMap(AccentChoice.init(rawValue:)) ?? .teal
    }
}
