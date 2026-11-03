import Foundation

public struct Mapping: Equatable, Sendable {
    public var single: RemoteAction = .showOrEasy
    public var double: RemoteAction = .again
    public var triple: RemoteAction = .undo

    public init() {}

    public init(defaults: UserDefaults) {
        for gesture in Gesture.allCases {
            if let raw = defaults.string(forKey: "mapping.\(gesture.rawValue)"),
               let action = RemoteAction(rawValue: raw) {
                self[gesture] = action
            }
        }
    }

    public subscript(_ gesture: Gesture) -> RemoteAction {
        get {
            switch gesture {
            case .single: return single
            case .double: return double
            case .triple: return triple
            }
        }
        set {
            switch gesture {
            case .single: single = newValue
            case .double: double = newValue
            case .triple: triple = newValue
            }
        }
    }

    public func save(to defaults: UserDefaults) {
        for gesture in Gesture.allCases {
            defaults.set(self[gesture].rawValue, forKey: "mapping.\(gesture.rawValue)")
        }
    }

    public static func validatedEase(_ value: Int) -> Int { value == 3 ? 3 : 4 }
}
