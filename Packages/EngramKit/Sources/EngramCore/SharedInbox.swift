import Foundation

public struct SharedItem: Codable, Sendable, Equatable {
    public let text: String
    public let link: String?
    public let createdAt: Date
    public init(text: String, link: String?, createdAt: Date) {
        self.text = text
        self.link = link
        self.createdAt = createdAt
    }
    public var noteText: String { "" }
}

public struct SharedInbox: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func add(_ item: SharedItem) throws {}
    public func drain() -> [SharedItem] { [] }
}
