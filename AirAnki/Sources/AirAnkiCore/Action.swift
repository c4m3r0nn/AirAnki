public enum RemoteAction: Equatable, RawRepresentable, CaseIterable, Sendable {
    case showOrGrade(ease: Int)
    // Retained solely for saved, experimental stem mappings.
    case showOrEasy, again, undo, none, reveal

    public static let allCases: [RemoteAction] = [.showOrEasy, .again, .undo, .none]
    public init?(rawValue: String) {
        switch rawValue {
        case "showOrEasy": self = .showOrEasy
        case "again": self = .again
        case "undo": self = .undo
        case "reveal": self = .reveal
        case "none": self = .none
        default:
            guard rawValue.hasPrefix("showOrGrade:"),
                  let ease = Int(rawValue.dropFirst("showOrGrade:".count)), (1...4).contains(ease) else { return nil }
            self = .showOrGrade(ease: ease)
        }
    }
    public var rawValue: String {
        switch self {
        case .showOrGrade(let ease): return "showOrGrade:\(ease)"
        case .showOrEasy: return "showOrEasy"
        case .again: return "again"
        case .undo: return "undo"
        case .reveal: return "reveal"
        case .none: return "none"
        }
    }

    public var title: String {
        switch self {
        case .showOrGrade(let ease): return "Show answer / \(ActionFeedback.graded(ease).title)"
        case .showOrEasy: return "Show answer / grade"
        case .again: return "Again"
        case .undo: return "Undo"
        case .reveal: return "Show answer"
        case .none: return "Do nothing"
        }
    }
}

public enum ActionFeedback: Equatable, Sendable {
    case showedAnswer, graded(Int), undone, error, unclear

    public var title: String {
        switch self {
        case .showedAnswer: return "Showed answer"
        case .graded(1): return "Graded Again"
        case .graded(3): return "Graded Good"
        case .graded(4): return "Graded Easy"
        case .graded(let ease): return "Graded \(ease)"
        case .undone: return "Undo"
        case .error: return "Error"
        case .unclear: return "unclear flick — try again"
        }
    }

    public var symbol: String {
        switch self {
        case .showedAnswer: return "👁"
        case .graded(1): return "✗"
        case .graded: return "✓"
        case .undone: return "↶"
        case .error: return "!"
        case .unclear: return "?"
        }
    }
}

public enum GestureOutcome: Equatable, Sendable {
    case discarded(String), notReviewing, completed(ActionFeedback)
    case failed(String, completedAction: ActionFeedback? = nil)

    public var wasAccepted: Bool {
        if case .discarded = self { return false }
        return true
    }

    public var title: String {
        switch self {
        case .discarded(let reason): return "Ignored (\(reason))"
        case .notReviewing: return "No action (not reviewing)"
        case .completed(let action): return action.title
        case .failed(let message, let completedAction):
            return completedAction.map { "\($0.title); status refresh failed: \(message)" } ?? "Error: \(message)"
        }
    }
}
