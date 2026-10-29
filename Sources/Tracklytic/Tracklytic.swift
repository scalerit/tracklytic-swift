import Combine
import Foundation

public enum TracklyticClientError: Error {
  case missingAccessToken
  case invalidURL
  case invalidPipeline
  case invalidStepUpdate
  case invalidActionIndex
}

/// API tokens write telemetry; user access tokens authorize reads and management.
public final class TracklyticClient {
  public static let defaultBaseURL = Constants.baseURL
  private let project: String
  private let token: String
  private let accessToken: String?
  private let baseURL: URL
  private let session: URLSession
  private var disabled = false

  public init(
    project: String, token: String, accessToken: String? = nil,
    baseURL: URL = TracklyticClient.defaultBaseURL, session: URLSession = .shared
  ) {
    self.project = project
    self.token = token
    self.accessToken = accessToken
    self.baseURL = baseURL
    self.session = session
  }
  public func disableTracking() { disabled = true }
  public func enableTracking() { disabled = false }
  public func getProject() -> String { project }

  private func object<T: Encodable>(_ value: T) throws -> JSONObject {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    return try JSONDecoder().decode(JSONObject.self, from: encoder.encode(value))
  }
  private func request(
    _ method: String, _ path: [String], body: JSONObject? = nil, query: [String: String] = [:],
    user: Bool = false, projectBody: Bool = false, projectQuery: Bool = false
  ) throws -> URLRequest {
    let credential: String
    if user {
      guard let accessToken = accessToken, !accessToken.isEmpty else {
        throw TracklyticClientError.missingAccessToken
      }
      credential = accessToken
    } else {
      credential = token
    }
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw TracklyticClientError.invalidURL
    }
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    components.query = nil
    components.fragment = nil
    while components.percentEncodedPath.hasSuffix("/") {
      components.percentEncodedPath.removeLast()
    }
    for part in path {
      guard !part.isEmpty, let escaped = part.addingPercentEncoding(withAllowedCharacters: allowed)
      else { throw TracklyticClientError.invalidURL }
      components.percentEncodedPath += "/" + escaped
    }
    var query = query
    if projectQuery { query["project"] = project }
    if !query.isEmpty {
      components.queryItems = query.sorted { $0.key < $1.key }.map {
        URLQueryItem(name: $0.key, value: $0.value)
      }
    }
    guard let url = components.url else { throw TracklyticClientError.invalidURL }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if var body = body {
      if projectBody { body["project"] = AnyCodable(project) }
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONEncoder().encode(body)
    }
    return request
  }
  private func publisher<T: Decodable>(
    _ build: () throws -> URLRequest, as: T.Type, disabledResult: Data? = nil
  ) -> AnyPublisher<T, Error> {
    if disabled, let data = disabledResult {
      do {
        return Just(try JSONDecoder().decode(T.self, from: data)).setFailureType(to: Error.self)
          .eraseToAnyPublisher()
      } catch { return Fail(error: error).eraseToAnyPublisher() }
    }
    do {
      return session.dataTaskPublisher(for: try build())
        .tryMap { try validateResponse(data: $0.data, response: $0.response) }
        .decode(type: T.self, decoder: JSONDecoder()).eraseToAnyPublisher()
    } catch { return Fail(error: error).eraseToAnyPublisher() }
  }
  /// Publish telemetry. Use createEvent when a pipeline event's returned ID is needed.
  public func track(options: TrackOptions) -> AnyPublisher<Bool, Error> {
    createEvent(options: options).map { _ in true }.eraseToAnyPublisher()
  }
  public func createEvent(options: TrackOptions) -> AnyPublisher<CreateEventResponse, Error> {
    publisher(
      { try request("POST", ["event"], body: object(options), projectBody: true) },
      as: CreateEventResponse.self, disabledResult: Data("{}".utf8))
  }
  public func identify(options: IdentifyOptions) -> AnyPublisher<Bool, Error> {
    publisher(
      { try request("POST", ["identify"], body: object(options), projectBody: true) },
      as: JSONObject.self, disabledResult: Data("{}".utf8)
    ).map { _ in true }.eraseToAnyPublisher()
  }
}

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
extension TracklyticClient {
  private func send<T: Decodable>(
    _ method: String, _ path: [String], body: JSONObject? = nil, query: [String: String] = [:],
    user: Bool = false, projectBody: Bool = false, projectQuery: Bool = false,
    telemetry: Bool = false, as: T.Type
  ) async throws -> T {
    if disabled && telemetry { return try JSONDecoder().decode(T.self, from: Data("{}".utf8)) }
    let req = try request(
      method, path, body: body, query: query, user: user, projectBody: projectBody,
      projectQuery: projectQuery)
    let (data, response) = try await session.data(for: req)
    return try JSONDecoder().decode(T.self, from: validateResponse(data: data, response: response))
  }
  @discardableResult public func track(options: TrackOptions) async throws -> Bool {
    let _: CreateEventResponse = try await createEvent(options: options)
    return true
  }
  public func createEvent(options: TrackOptions) async throws -> CreateEventResponse {
    try await send(
      "POST", ["event"], body: object(options), projectBody: true, telemetry: true,
      as: CreateEventResponse.self)
  }
  /// Creates a pipeline event. Stages group display; requires defines dependencies.
  public func createPipeline(options: TrackOptions) async throws -> CreateEventResponse {
    guard let steps = options.steps, !steps.isEmpty else {
      throw TracklyticClientError.invalidPipeline
    }
    return try await createEvent(options: options)
  }
  /// API-token step update, intended for CI workers and external execution systems.
  public func updateStep(eventId: String, options: StepUpdate) async throws -> JSONObject {
    guard options.status != nil || !(options.steps?.isEmpty ?? true) else {
      throw TracklyticClientError.invalidStepUpdate
    }
    return try await send(
      "POST", ["event", eventId, "step"], body: object(options), telemetry: true,
      as: JSONObject.self)
  }
  /// Same mutation authorized with a user access token.
  public func updateStepAsUser(eventId: String, options: StepUpdate) async throws -> JSONObject {
    guard options.status != nil || !(options.steps?.isEmpty ?? true) else {
      throw TracklyticClientError.invalidStepUpdate
    }
    return try await send(
      "PATCH", ["event", eventId, "step"], body: object(options), user: true, as: JSONObject.self)
  }
  public func getEvents(query: [String: String] = [:]) async throws -> JSONObject {
    try await send(
      "GET", ["event", "query"], query: query, user: true, projectQuery: true, as: JSONObject.self)
  }
  public func getEvent(eventId: String) async throws -> JSONObject {
    try await send("GET", ["event", eventId], user: true, as: JSONObject.self)
  }
  /// Patch fields follow the API schema; use AnyCodable(NSNull()) to clear badge.
  public func updateEvent(eventId: String, changes: JSONObject) async throws -> JSONObject {
    try await send("PATCH", ["event", eventId], body: changes, user: true, as: JSONObject.self)
  }
  public func deleteEvent(eventId: String) async throws {
    let _: JSONObject = try await send(
      "DELETE", ["event", eventId], user: true, as: JSONObject.self)
  }
  public func addLog(eventId: String, log: EventLog) async throws -> JSONObject {
    try await send(
      "POST", ["event", eventId, "logs"], body: object(log), user: true, as: JSONObject.self)
  }
  public func executeAction(
    eventId: String, actionIndex: Int, options: ActionInputs = ActionInputs()
  ) async throws -> JSONObject {
    guard actionIndex >= 0 else { throw TracklyticClientError.invalidActionIndex }
    return try await send(
      "POST", ["event", eventId, "actions", String(actionIndex), "execute"], body: object(options),
      user: true, as: JSONObject.self)
  }
  public func executeStepAction(
    eventId: String, stepId: String, actionIndex: Int, options: ActionInputs = ActionInputs()
  ) async throws -> JSONObject {
    guard actionIndex >= 0 else { throw TracklyticClientError.invalidActionIndex }
    return try await send(
      "POST", ["event", eventId, "steps", stepId, "actions", String(actionIndex), "execute"],
      body: object(options), user: true, as: JSONObject.self)
  }
  @discardableResult public func identify(options: IdentifyOptions) async throws -> Bool {
    let _: JSONObject = try await send(
      "POST", ["identify"], body: object(options), projectBody: true, telemetry: true,
      as: JSONObject.self)
    return true
  }
  public func clearAvatar(userId: String, properties: JSONObject = [:]) async throws {
    let _: JSONObject = try await send(
      "POST", ["identify"],
      body: [
        "userId": AnyCodable(userId), "properties": AnyCodable(properties),
        "avatar": AnyCodable(NSNull()),
      ], projectBody: true, telemetry: true, as: JSONObject.self)
  }
  public func getProfiles(query: [String: String] = [:]) async throws -> JSONObject {
    try await send(
      "GET", ["identify", "query"], query: query, user: true, projectQuery: true,
      as: JSONObject.self)
  }
  public func getProfile(userId: String) async throws -> JSONObject {
    try await send(
      "GET", ["identify", "profile"], query: ["userId": userId], user: true, projectQuery: true,
      as: JSONObject.self)
  }
  public func deleteProfile(userId: String) async throws {
    let _: JSONObject = try await send(
      "DELETE", ["identify", "profile"], query: ["userId": userId], user: true, projectQuery: true,
      as: JSONObject.self)
  }
  public func trackInsight(title: String, value: AnyCodable, notify: Bool? = nil) async throws {
    guard
      value.value is String || (value.value is NSNumber && !(value.value is Bool))
        || value.value is Int || value.value is Double
    else {
      throw EncodingError.invalidValue(
        value.value,
        .init(codingPath: [], debugDescription: "Insight value must be a string or number"))
    }
    if value.value is Bool {
      throw EncodingError.invalidValue(
        value.value, .init(codingPath: [], debugDescription: "Boolean insights are unsupported"))
    }
    var body: JSONObject = ["title": AnyCodable(title), "value": value]
    if let notify = notify { body["notify"] = AnyCodable(notify) }
    let _: JSONObject = try await send(
      "POST", ["insight"], body: body, projectBody: true, telemetry: true, as: JSONObject.self)
  }
  public func incrementInsight(title: String, value: Double = 1, notify: Bool? = nil) async throws {
    var body: JSONObject = ["title": AnyCodable(title), "value": AnyCodable(["$inc": value])]
    if let notify = notify { body["notify"] = AnyCodable(notify) }
    let _: JSONObject = try await send(
      "PATCH", ["insight", "mutate"], body: body, projectBody: true, telemetry: true,
      as: JSONObject.self)
  }
  public func getInsights(query: [String: String] = [:]) async throws -> JSONObject {
    try await send(
      "GET", ["insight", "query"], query: query, user: true, projectQuery: true, as: JSONObject.self
    )
  }
  public func getInsight(title: String) async throws -> JSONObject {
    try await send(
      "GET", ["insight", "insight"], query: ["title": title], user: true, projectQuery: true,
      as: JSONObject.self)
  }
  public func deleteInsight(title: String) async throws {
    let _: JSONObject = try await send(
      "DELETE", ["insight", "insight"], query: ["title": title], user: true, projectQuery: true,
      as: JSONObject.self)
  }
}
