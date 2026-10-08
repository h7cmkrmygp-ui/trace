import Foundation

public enum CategoryPalette {
    public static let count = 10
    public static func index(for name: String) -> Int { 0 }
    public static func index(forPath path: String) -> Int { 0 }
}

public enum BrainMotion {
    public static func orbit(_ point: (x: Double, y: Double), around anchor: (x: Double, y: Double), seed: UInt64,
                             time: Double) -> (x: Double, y: Double) { point }
    public static func pulse(seed: UInt64, time: Double) -> Double { 0 }
    public static func signal(seed: UInt64, time: Double) -> Double? { nil }
}
