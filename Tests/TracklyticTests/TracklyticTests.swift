import Combine
import XCTest

@testable import Tracklytic

final class TracklyticTests: XCTestCase {
  func testUserIdEncodesWithCanonicalCamelCaseField() throws {
    let options = TrackOptions(channel: "events", event: "naming.test", userId: "customer-42")
    let data = try JSONEncoder().encode(options)
    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(payload["userId"] as? String, "customer-42")
    XCTAssertNil(payload["user_id"])
  }
}

private final class MockURLProtocol: URLProtocol {
  static var handler: ((URLRequest) throws -> (Int, Data))?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let (status, data) = try Self.handler!(request)
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil,
        headerFields: ["Content-Type": "application/json"])!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
final class APIContractTests: XCTestCase {
  private func client(accessToken: String? = "user-jwt") -> TracklyticClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return TracklyticClient(
      project: "my-project", token: "api-token", accessToken: accessToken,
      session: URLSession(configuration: config))
  }
  private func body(_ request: URLRequest) throws -> [String: Any] {
    var data = request.httpBody
    if data == nil, let stream = request.httpBodyStream {
      stream.open()
      defer { stream.close() }
      var result = Data()
      var buffer = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        result.append(buffer, count: count)
      }
      data = result
    }
    return try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(data)) as? [String: Any])
  }
  override func tearDown() {
    MockURLProtocol.handler = nil
    super.tearDown()
  }

  func testPipelineCreationKeepsIDAndCurrentEventFields() async throws {
    MockURLProtocol.handler = { request in
      XCTAssertEqual(request.url?.path, "/v1/event")
      XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer api-token")
      let body = try self.body(request)
      XCTAssertEqual(body["project"] as? String, "my-project")
      XCTAssertEqual(body["userId"] as? String, "customer-42")
      XCTAssertEqual(body["timestamp"] as? Double, 1_700_000_000_125)
      XCTAssertNil(body["icon"])
      XCTAssertNil(body["user_id"])
      XCTAssertEqual(body["logLevel"] as? String, "critical")
      XCTAssertEqual((body["badge"] as? [String: Any])?["color"] as? String, "danger")
      let tags = try XCTUnwrap(body["tags"] as? [String: Any])
      XCTAssertEqual(tags["attempt"] as? Int, 3)
      XCTAssertEqual(tags["enabled"] as? Bool, true)
      XCTAssertTrue(tags["empty"] is NSNull)
      XCTAssertEqual((body["steps"] as? [[String: Any]])?.last?["requires"] as? [String], ["build"])
      return (201, Data(#"{"id":"event-42","status":"waiting","pipeline":{"timeout":300}}"#.utf8))
    }
    let result = try await client().createPipeline(
      options: TrackOptions(
        channel: "deployments", event: "Deployment", userId: "customer-42",
        tags: [
          "attempt": AnyCodable(3), "enabled": AnyCodable(true), "empty": AnyCodable(NSNull()),
        ], timestamp: Date(timeIntervalSince1970: 1_700_000_000.125), logLevel: .critical,
        badge: Badge(title: "Deployment", color: .danger),
        steps: [
          PipelineStep(id: "build", name: "Build", stage: "build"),
          PipelineStep(id: "deploy", name: "Deploy", stage: "deploy", requires: ["build"]),
        ], pipeline: PipelineConfig(timeout: 300)))
    XCTAssertEqual(result.id, "event-42")
    XCTAssertEqual(result.status, .waiting)
  }
  func testOrdinaryEventEmptyResponseRemainsSuccessful() async throws {
    MockURLProtocol.handler = { _ in (201, Data("{}".utf8)) }
    let success = try await client().track(
      options: TrackOptions(channel: "events", event: "Created"))
    XCTAssertTrue(success)
  }
  func testStepAPIAndUserRoutesUseDistinctCredentials() async throws {
    var calls = 0
    MockURLProtocol.handler = { request in
      calls += 1
      XCTAssertEqual(request.url?.path, "/v1/event/event-42/step")
      XCTAssertEqual(request.httpMethod, calls == 1 ? "POST" : "PATCH")
      XCTAssertEqual(
        request.value(forHTTPHeaderField: "Authorization"),
        calls == 1 ? "Bearer api-token" : "Bearer user-jwt")
      XCTAssertEqual(try self.body(request)["id"] as? String, "build")
      return (200, Data("{}".utf8))
    }
    let api = client()
    _ = try await api.updateStep(
      eventId: "event-42", options: StepUpdate(id: "build", status: .running))
    _ = try await api.updateStepAsUser(
      eventId: "event-42", options: StepUpdate(id: "build", status: .success))
    XCTAssertEqual(calls, 2)
  }
  func testActionConfirmationAndFormInputs() async throws {
    MockURLProtocol.handler = { request in
      XCTAssertEqual(request.url?.path, "/v1/event/event-42/steps/approve/actions/0/execute")
      let body = try self.body(request)
      XCTAssertEqual(body["confirmed"] as? Bool, true)
      XCTAssertEqual((body["inputs"] as? [String: Any])?["version"] as? String, "2.0")
      return (200, Data(#"{"success":false,"results":[{"success":false}]}"#.utf8))
    }
    let result = try await client().executeStepAction(
      eventId: "event-42", stepId: "approve", actionIndex: 0,
      options: ActionInputs(inputs: ["version": AnyCodable("2.0")], confirmed: true))
    XCTAssertEqual(result["success"], AnyCodable(false))
  }
  func testProtectedCallsNeverFallBackToAPIToken() async throws {
    MockURLProtocol.handler = { _ in
      XCTFail("No network request expected")
      return (200, Data("{}".utf8))
    }
    do {
      _ = try await client(accessToken: nil).getEvent(eventId: "event-42")
      XCTFail("Expected missing credential")
    } catch TracklyticClientError.missingAccessToken {}
  }
  func testQueryEncodingAndNoBodyOnDelete204() async throws {
    var calls = 0
    MockURLProtocol.handler = { request in
      calls += 1
      let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
      XCTAssertEqual(query?.first(where: { $0.name == "project" })?.value, "my-project")
      XCTAssertEqual(query?.first(where: { $0.name == "userId" })?.value, "customer+a&b")
      if calls == 1 {
        XCTAssertEqual(request.httpMethod, "GET")
        return (200, Data(#"{"userId":"customer+a&b"}"#.utf8))
      }
      XCTAssertEqual(request.httpMethod, "DELETE")
      return (204, Data())
    }
    let api = client()
    _ = try await api.getProfile(userId: "customer+a&b")
    try await api.deleteProfile(userId: "customer+a&b")
  }
  func testHTTPErrorRetainsStatusAndServerMessage() async throws {
    MockURLProtocol.handler = { _ in
      (409, Data(#"{"code":409,"message":"Maximum runs reached"}"#.utf8))
    }
    do {
      _ = try await client().getEvent(eventId: "event-42")
      XCTFail("Expected API error")
    } catch let error as TracklyticHTTPError {
      XCTAssertEqual(error.statusCode, 409)
      XCTAssertEqual(error.errorDescription, "Maximum runs reached")
    }
  }
  func testDisabledTelemetryMakesNoRequests() async throws {
    MockURLProtocol.handler = { _ in
      XCTFail("Disabled telemetry must not send")
      return (200, Data("{}".utf8))
    }
    let api = client()
    api.disableTracking()
    let success = try await api.track(options: TrackOptions(channel: "events", event: "Disabled"))
    XCTAssertTrue(success)
    let result = try await api.updateStep(
      eventId: "event-42", options: StepUpdate(id: "build", status: .success))
    XCTAssertTrue(result.isEmpty)
    try await api.incrementInsight(title: "Builds")
  }
  func testLinkOmitsExecutionAndJSONRoundTripsNestedValues() throws {
    let action = ActionComponent(
      type: .link, properties: ["url": AnyCodable("https://example.com/build")])
    let object =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(action)) as? [String: Any]
    XCTAssertNil(object?["action"])
    let value = AnyCodable(["list": [NSNull(), true, 2, "value"]] as [String: Any])
    XCTAssertEqual(
      try JSONDecoder().decode(AnyCodable.self, from: JSONEncoder().encode(value)), value)
  }
  func testInsightIncrementAndAvatarRemovalContracts() async throws {
    var calls = 0
    MockURLProtocol.handler = { request in
      calls += 1
      let body = try self.body(request)
      if calls == 1 {
        XCTAssertEqual(request.url?.path, "/v1/insight/mutate")
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual((body["value"] as? [String: Any])?["$inc"] as? Double, 2)
        XCTAssertNil(body["icon"])
      } else {
        XCTAssertTrue(body["avatar"] is NSNull)
      }
      return (200, Data("{}".utf8))
    }
    let api = client()
    try await api.incrementInsight(title: "Builds", value: 2)
    try await api.clearAvatar(userId: "customer-42")
  }
  func testMalformedInputsFailLocally() async throws {
    let api = client()
    do {
      _ = try await api.createPipeline(options: TrackOptions(channel: "events", event: "Invalid"))
      XCTFail("Expected invalid pipeline")
    } catch TracklyticClientError.invalidPipeline {}
    do {
      _ = try await api.updateStep(eventId: "event-42", options: StepUpdate(id: "build"))
      XCTFail("Expected invalid update")
    } catch TracklyticClientError.invalidStepUpdate {}
    do {
      _ = try await api.executeAction(eventId: "event-42", actionIndex: -1)
      XCTFail("Expected invalid index")
    } catch TracklyticClientError.invalidActionIndex {}
  }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension APIContractTests {
  func testCombineTrackPublishesSuccessAndEncodingFailure() throws {
    MockURLProtocol.handler = { request in
      XCTAssertEqual(request.url?.path, "/v1/event")
      return (201, Data("{}".utf8))
    }
    let api = client()
    let completed = expectation(description: "Combine event completed")
    var cancellables = Set<AnyCancellable>()
    let publisher: AnyPublisher<Bool, Error> = api.track(
      options: TrackOptions(channel: "events", event: "Combine"))
    publisher.sink(
      receiveCompletion: { completion in
        if case .failure(let error) = completion { XCTFail("Unexpected error: \(error)") }
        completed.fulfill()
      }, receiveValue: { XCTAssertTrue($0) }
    ).store(in: &cancellables)
    wait(for: [completed], timeout: 5)

    MockURLProtocol.handler = { _ in
      XCTFail("Invalid JSON must not be sent")
      return (201, Data("{}".utf8))
    }
    let rejected = expectation(description: "Combine encoding failure")
    let invalid: AnyPublisher<Bool, Error> = api.track(
      options: TrackOptions(
        channel: "events", event: "Invalid", tags: ["invalid": AnyCodable(Date())]))
    invalid.sink(
      receiveCompletion: { completion in
        if case .finished = completion { XCTFail("Expected encoding failure") }
        rejected.fulfill()
      }, receiveValue: { _ in XCTFail("No value expected") }
    ).store(in: &cancellables)
    wait(for: [rejected], timeout: 5)
  }

  func testInsightAcceptsNumbersAndRejectsBoolean() async throws {
    MockURLProtocol.handler = { request in
      XCTAssertEqual(request.url?.path, "/v1/insight")
      XCTAssertEqual(try self.body(request)["value"] as? Double, 1200)
      return (201, Data("{}".utf8))
    }
    let api = client()
    try await api.trackInsight(title: "Users", value: AnyCodable(1200))
    do {
      try await api.trackInsight(title: "Users", value: AnyCodable(true))
      XCTFail("Expected invalid Boolean value")
    } catch is EncodingError {}
  }
}
