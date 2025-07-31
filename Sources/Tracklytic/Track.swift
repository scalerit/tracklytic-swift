import Foundation

/// Options for publishing Tracklytic events
public struct TrackOptions: Codable, Equatable {
    let channel: String
    let event: String
    let description: String?
    let user_id: String?
    let icon: String?
    let tags: [String: String]?
    let notify: Bool?
    let parser: String?
    let timestamp: Date?
    var project: String?
    
    /// Creates a `TrackOptions` object to send to Tracklytic
    /// - Parameters:
    ///   - channel: Channel ID (required)
    ///   - event: Event name
    ///   - description: Event description (default `nil`)
    ///   - user_id: User ID (default `nil`)
    ///   - icon: Event icon (emoji) (default `nil`)
    ///   - tags: Event tags (default `nil`)
    ///   - notify: Send push notification (default `nil`)
    ///   - parser: Parser for description (default `nil`)
    ///   - timestamp: Event timestamp (default `nil`)
    public init(
        channel: String,
        event: String,
        description: String? = nil,
        user_id: String? = nil,
        icon: String? = nil,
        tags: [String: String]? = nil,
        notify: Bool? = nil,
        parser: String? = nil,
        timestamp: Date? = nil
    ) {
        self.channel = channel
        self.event = event
        self.description = description
        self.user_id = user_id
        self.icon = icon
        self.tags = tags
        self.notify = notify
        self.parser = parser
        self.timestamp = timestamp
    }
} 