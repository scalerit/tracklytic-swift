import Foundation

/// Action component types
public enum ActionComponentType: String, Codable, CaseIterable {
    case button = "button"
    case form = "form"
    case custom = "custom"
}

/// Action execution types
public enum ActionExecutionType: String, Codable, CaseIterable {
    case webhook = "webhook"
    case url = "url"
    case notification = "notification"
}

/// Action execution definition
public struct ActionExecution: Codable, Equatable {
    public let type: ActionExecutionType
    public let properties: [String: AnyCodable]
    
    public init(type: ActionExecutionType, properties: [String: AnyCodable] = [:]) {
        self.type = type
        self.properties = properties
    }
}

/// Action component definition
public struct ActionComponent: Codable, Equatable {
    public let type: ActionComponentType
    public let properties: [String: AnyCodable]
    public let action: [ActionExecution]
    
    public init(type: ActionComponentType, properties: [String: AnyCodable] = [:], action: [ActionExecution] = []) {
        self.type = type
        self.properties = properties
        self.action = action
    }
}

/// Helper for encoding/decoding Any type
public struct AnyCodable: Codable, Equatable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.typeMismatch(AnyCodable.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else if let array = value as? [Any] {
            try container.encode(array.map { AnyCodable($0) })
        } else if let dict = value as? [String: Any] {
            try container.encode(dict.mapValues { AnyCodable($0) })
        } else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}

/// Options for publishing Tracklytic events
public struct TrackOptions: Codable, Equatable {
    let channel: String
    let event: String
    let description: String?
    let user_id: String?
    let icon: String?
    let tags: [String: String]?
    let notify: Bool?
    let actions: [ActionComponent]?
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
    ///   - actions: Interactive actions available for this event (default `nil`)
    ///   - timestamp: Event timestamp (default `nil`)
    public init(
        channel: String,
        event: String,
        description: String? = nil,
        user_id: String? = nil,
        icon: String? = nil,
        tags: [String: String]? = nil,
        notify: Bool? = nil,
        actions: [ActionComponent]? = nil,
        timestamp: Date? = nil
    ) {
        self.channel = channel
        self.event = event
        self.description = description
        self.user_id = user_id
        self.icon = icon
        self.tags = tags
        self.notify = notify
        self.actions = actions
        self.timestamp = timestamp
    }
} 