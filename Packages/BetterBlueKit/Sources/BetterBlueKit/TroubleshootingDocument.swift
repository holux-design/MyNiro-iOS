import Foundation

public enum TroubleshootingDocument {
    public static let markdown: String = "Troubleshooting content is unavailable in this build."

    public struct Section: Identifiable, Sendable {
        public let title: String
        public let body: String
        public var id: String { title }
    }

    public static let sections: [Section] = []
}
