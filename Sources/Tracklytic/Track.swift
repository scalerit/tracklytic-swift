import Foundation

/// A JSON value, including nested objects, arrays and null.
public struct AnyCodable: Codable, Equatable {
  public let value: Any
  public init(_ value: Any) { self.value = value }
  public init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() {
      value = NSNull()
    } else if let v = try? c.decode(Bool.self) {
      value = v
    } else if let v = try? c.decode(Int.self) {
      value = v
    } else if let v = try? c.decode(Double.self) {
      value = v
    } else if let v = try? c.decode(String.self) {
      value = v
    } else if let v = try? c.decode([AnyCodable].self) {
      value = v.map(\.value)
    } else {
      value = try c.decode([String: AnyCodable].self).mapValues(\.value)
    }
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch value {
    case is NSNull: try c.encodeNil()
    case let v as Bool: try c.encode(v)
    case let v as String: try c.encode(v)
    case let v as Int: try c.encode(v)
    case let v as Double: try c.encode(v)
    case let v as [AnyCodable]: try c.encode(v)
    case let v as [String: AnyCodable]: try c.encode(v)
    case let v as [Any]: try c.encode(v.map(AnyCodable.init))
    case let v as [String: Any]: try c.encode(v.mapValues(AnyCodable.init))
    default:
      throw EncodingError.invalidValue(
        value, .init(codingPath: encoder.codingPath, debugDescription: "Unsupported JSON value"))
    }
  }
  public static func == (lhs: Self, rhs: Self) -> Bool {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let a = try? encoder.encode(lhs), let b = try? encoder.encode(rhs) else { return false }
    return a == b
  }
}

public enum LogLevel: String, Codable, CaseIterable { case info, warning, failed, critical }
public enum BadgeColor: String, Codable, CaseIterable {
  case primary, success, danger, alert, info, neutral
}
public enum EventStatus: String, Codable {
  case pending, active, completed, failed, cancelled, waiting, running, success
  case timedOut = "timed_out"
}
public enum StepStatus: String, Codable, CaseIterable {
  case waiting, running, success, failed, skipped, cancelled
}
public enum LogType: String, Codable { case info, success, warning, error, manual }
public struct Badge: Codable, Equatable {
  public var title: String
  public var color: BadgeColor
  public init(title: String, color: BadgeColor) {
    self.title = title
    self.color = color
  }
}
public enum ActionComponentType: String, Codable, CaseIterable { case button, form, custom, link }
public enum ActionExecutionType: String, Codable, CaseIterable { case webhook, url, notification }
public struct ActionExecution: Codable, Equatable {
  public var type: ActionExecutionType
  /// Webhook URL, method, headers, body, bodyType, timeout, expects, or notification properties.
  public var properties: [String: AnyCodable]
  public init(type: ActionExecutionType, properties: [String: AnyCodable] = [:]) {
    self.type = type
    self.properties = properties
  }
}
public struct ActionComponent: Codable, Equatable {
  public var type: ActionComponentType
  /// Button text, link URL, or form fields and other presentation properties.
  public var properties: [String: AnyCodable]
  public var action: [ActionExecution]?
  public var maxRuns: Int?
  public var allowRetryOnFailure: Bool?
  /// ISO 8601 date string.
  public var expiresAt: String?
  public var stopOnFailure: Bool?
  public var confirmation: String?
  public init(
    type: ActionComponentType, properties: [String: AnyCodable] = [:],
    action: [ActionExecution]? = nil, maxRuns: Int? = nil, allowRetryOnFailure: Bool? = nil,
    expiresAt: String? = nil, stopOnFailure: Bool? = nil, confirmation: String? = nil
  ) {
    self.type = type
    self.properties = properties
    self.action = action
    self.maxRuns = maxRuns
    self.allowRetryOnFailure = allowRetryOnFailure
    self.expiresAt = expiresAt
    self.stopOnFailure = stopOnFailure
    self.confirmation = confirmation
  }
}
public struct EventLog: Codable, Equatable {
  public var type: LogType
  public var message: String
  public var details: [String: AnyCodable]?
  public var actionId: String?
  public var userId: String?
  public init(
    type: LogType, message: String, details: [String: AnyCodable]? = nil, actionId: String? = nil,
    userId: String? = nil
  ) {
    self.type = type
    self.message = message
    self.details = details
    self.actionId = actionId
    self.userId = userId
  }
}
public struct PipelineStep: Codable, Equatable {
  public var id: String
  public var name: String
  public var stage: String
  public var description: String?
  public var required: Bool?
  public var allowFailure: Bool?
  public var requires: [String]?
  public var status: StepStatus?
  public var actions: [ActionComponent]?
  public init(
    id: String, name: String, stage: String, description: String? = nil, required: Bool? = nil,
    allowFailure: Bool? = nil, requires: [String]? = nil, status: StepStatus? = nil,
    actions: [ActionComponent]? = nil
  ) {
    self.id = id
    self.name = name
    self.stage = stage
    self.description = description
    self.required = required
    self.allowFailure = allowFailure
    self.requires = requires
    self.status = status
    self.actions = actions
  }
}
public struct TimeoutAlert: Codable, Equatable {
  public var logLevel: LogLevel
  public var notify: Bool?
  public init(logLevel: LogLevel = .failed, notify: Bool? = nil) {
    self.logLevel = logLevel
    self.notify = notify
  }
}
public struct PipelineConfig: Codable, Equatable {
  /// Timeout in seconds (1...31536000).
  public var timeout: Int?
  public var timeoutAlert: TimeoutAlert?
  public init(timeout: Int? = nil, timeoutAlert: TimeoutAlert? = nil) {
    self.timeout = timeout
    self.timeoutAlert = timeoutAlert
  }
}
public struct StepUpdate: Codable, Equatable {
  public var id: String
  public var status: StepStatus?
  public var message: String?
  public var steps: [PipelineStep]?
  public init(
    id: String, status: StepStatus? = nil, message: String? = nil, steps: [PipelineStep]? = nil
  ) {
    self.id = id
    self.status = status
    self.message = message
    self.steps = steps
  }
}
public struct TrackOptions: Codable, Equatable {
  public var channel: String
  public var event: String
  public var description: String?
  public var userId: String?
  public var tags: [String: AnyCodable]?
  public var notify: Bool?
  public var actions: [ActionComponent]?
  /// Encoded as Unix milliseconds, as required by the API.
  public var timestamp: Date?
  public var logLevel: LogLevel?
  public var badge: Badge?
  public var status: EventStatus?
  public var logs: [EventLog]?
  public var steps: [PipelineStep]?
  public var pipeline: PipelineConfig?
  public init(
    channel: String, event: String, description: String? = nil, userId: String? = nil,
    tags: [String: AnyCodable]? = nil, notify: Bool? = nil, actions: [ActionComponent]? = nil,
    timestamp: Date? = nil, logLevel: LogLevel? = nil, badge: Badge? = nil,
    status: EventStatus? = nil, logs: [EventLog]? = nil, steps: [PipelineStep]? = nil,
    pipeline: PipelineConfig? = nil
  ) {
    self.channel = channel
    self.event = event
    self.description = description
    self.userId = userId
    self.tags = tags
    self.notify = notify
    self.actions = actions
    self.timestamp = timestamp
    self.logLevel = logLevel
    self.badge = badge
    self.status = status
    self.logs = logs
    self.steps = steps
    self.pipeline = pipeline
  }
}
public struct IdentifyOptions: Codable, Equatable {
  public var userId: String
  public var properties: [String: AnyCodable]
  /// Public HTTPS URL or supported Base64 image. Use clearAvatar to remove an avatar.
  public var avatar: String?
  public init(userId: String, properties: [String: AnyCodable], avatar: String? = nil) {
    self.userId = userId
    self.properties = properties
    self.avatar = avatar
  }
}
/// Ordinary events return an empty object; pipeline events also return their ID and state.
public struct CreateEventResponse: Codable, Equatable {
  public let id: String?
  public let status: EventStatus?
  public let pipeline: AnyCodable?
}
public struct ActionInputs: Codable, Equatable {
  public var inputs: [String: AnyCodable]
  public var confirmed: Bool?
  public init(inputs: [String: AnyCodable] = [:], confirmed: Bool? = nil) {
    self.inputs = inputs
    self.confirmed = confirmed
  }
}
/// Value returned by API read and mutation endpoints. Preserves polymorphic tags, populated references and action results.
public typealias JSONObject = [String: AnyCodable]
