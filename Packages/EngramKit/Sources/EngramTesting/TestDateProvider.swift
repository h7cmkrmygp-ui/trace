import EngramCore
import Foundation
import Synchronization

/// Horloge contrôlable pour les tests. Ne jamais utiliser dans l'app.
public final class TestDateProvider: DateProvider {
    private let current: Mutex<Date>

    public init(_ start: Date) {
        current = Mutex(start)
    }

    public func now() -> Date { current.withLock { $0 } }

    public func advance(by interval: TimeInterval) {
        current.withLock { $0 += interval }
    }
}
