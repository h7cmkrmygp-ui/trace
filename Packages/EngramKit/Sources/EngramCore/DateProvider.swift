import Foundation

/// Horloge injectable, pour pouvoir tester les règles liées au temps.
public protocol DateProvider: Sendable {
    func now() -> Date
}

public struct SystemDateProvider: DateProvider {
    public init() {}
    public func now() -> Date { Date() }
}
