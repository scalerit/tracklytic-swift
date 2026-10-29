# Tracklytic Swift

Swift client for the current Tracklytic v1 API. Includes events, pipelines, interactive actions, profiles, and insights. Version 2.0.0 updates the SDK to the current event and pipeline contract.

## Installation

Add `https://github.com/scalerit/tracklytic-swift.git` as a Swift Package Manager dependency with version `2.0.0` or later, then import `Tracklytic`. Existing Combine event tracking supports iOS 13, macOS 10.15, tvOS 13, and watchOS 6. The async API requires iOS 15, macOS 12, tvOS 15, or watchOS 8.

## Client and authentication

```swift
import Tracklytic

let tracklytic = TracklyticClient(
    project: "my-project",
    token: apiToken
)
```

Use a project slug and a channel slug such as `deployments`. API tokens authorize event creation, profile identification, insight writes, and `updateStep`. Reads, event management, and action execution require a separate user access JWT:

```swift
let management = TracklyticClient(
    project: "my-project",
    token: apiToken,
    accessToken: signedInUserAccessToken
)
```

Protected methods fail with `TracklyticClientError.missingAccessToken` when no access token is configured. They never fall back to an API token. Do not bundle privileged production credentials in an app; supply the appropriate runtime credentials or call Tracklytic from your backend. `baseURL` and `session` can be injected for a self-hosted API or testing.

## Events

```swift
let success = try await tracklytic.track(options: TrackOptions(
    channel: "deployments",
    event: "Release started",
    userId: "customer-42",
    tags: [
        "version": AnyCodable("2.4.0"),
        "attempt": AnyCodable(1),
        "production": AnyCodable(true)
    ],
    timestamp: Date(),
    logLevel: .info,
    badge: Badge(title: "Production", color: .primary)
))
```

`timestamp` is sent as Unix milliseconds. `notify` is omitted by default so the server applies its severity default: false for `info`/`warning`, true for `failed`/`critical`. Event status, logs, actions, pipeline steps and timeout configuration are supported. Events use badges instead of the removed `icon` field.

`track(options:)` retains its Boolean success result. Use `createEvent(options:)` to inspect the creation response. Ordinary events return `{}`; pipeline events return `id`, `status`, and pipeline metadata. Both methods also provide Combine publishers:

```swift
let publisher: AnyPublisher<Bool, Error> = tracklytic.track(
    options: TrackOptions(channel: "events", event: "Signed up")
)
```

Import `Combine` when using `AnyPublisher` and retain the subscription with your cancellables.

## Pipelines

```swift
let run = try await tracklytic.createPipeline(options: TrackOptions(
    channel: "deployments",
    event: "Production deployment",
    steps: [
        PipelineStep(id: "build", name: "Build", stage: "build"),
        PipelineStep(
            id: "deploy",
            name: "Deploy",
            stage: "release",
            requires: ["build"]
        )
    ],
    pipeline: PipelineConfig(
        timeout: 900,
        timeoutAlert: TimeoutAlert(logLevel: .failed, notify: true)
    )
))

if let eventId = run.id {
    _ = try await tracklytic.updateStep(
        eventId: eventId,
        options: StepUpdate(id: "build", status: .running)
    )
    // Run the actual build in your own system.
    _ = try await tracklytic.updateStep(
        eventId: eventId,
        options: StepUpdate(id: "build", status: .success, message: "Build passed")
    )
}
```

Stages group steps for display; only `requires` creates dependencies. Tracklytic records progress and executes declared actions, but does not automatically run external CI work. Step statuses are `waiting`, `running`, `success`, `failed`, `skipped`, and `cancelled`. Pipeline timeout is in seconds. Use `StepUpdate.steps` to append follow-up steps; it does not replace the graph. `updateStepAsUser` uses PATCH and the user JWT instead of the API-token POST route.

## Actions and forms

```swift
let approve = ActionComponent(
    type: .form,
    properties: [
        "buttonText": AnyCodable("Approve release"),
        "fields": AnyCodable([
            ["name": "version", "type": "text", "label": "Version", "required": true]
        ])
    ],
    action: [ActionExecution(type: .webhook, properties: [
        "url": AnyCodable("https://example.com/deploy"),
        "method": AnyCodable("POST"),
        "bodyType": AnyCodable("json"),
        "body": AnyCodable(["version": "{{inputs.version}}"]),
        "expects": AnyCodable(["code": 200])
    ])],
    maxRuns: 1,
    allowRetryOnFailure: true,
    confirmation: "Deploy this version?"
)
```

Components support `button`, `form`, `custom`, and `link`. Execution steps support `webhook`, `url`, and `notification`. Properties preserve the full API JSON schema, including form fields, webhook headers, expected responses, body types, and timeouts. Use `expiresAt` as an ISO 8601 string. Link components specify `properties.url` and omit `action`.

Execute as an authorized user:

```swift
let result = try await management.executeStepAction(
    eventId: eventId,
    stepId: "approve",
    actionIndex: 0,
    options: ActionInputs(
        inputs: ["version": AnyCodable("2.4.0")],
        confirmed: true
    )
)
```

Use `executeAction` for event-level actions. A successful HTTP response can still contain action failures: inspect the returned `success`, `results`, and execution summary rather than treating transport success as action success.

## Profiles and insights

```swift
try await tracklytic.identify(options: IdentifyOptions(
    userId: "customer-42",
    properties: ["name": AnyCodable("Alex"), "plan": AnyCodable("pro")],
    avatar: "https://example.com/avatar.png"
))
try await tracklytic.clearAvatar(userId: "customer-42")
try await tracklytic.trackInsight(title: "Active users", value: AnyCodable(1200))
try await tracklytic.incrementInsight(title: "Deployments", value: 1)
```

Avatar accepts a public HTTPS image URL or a supported Base64 PNG/JPEG/WebP image; the API enforces the 2 MiB decoded image limit. `clearAvatar` sends explicit JSON null. Insight values support strings and numbers; Boolean values are rejected. Increment sends `value: { "$inc": ... }`. Both insight write methods support `notify`.

## Read and management methods

All methods below use the configured user access JWT:

| Area | Methods |
| --- | --- |
| Events | `getEvents(query:)`, `getEvent(eventId:)`, `updateEvent(eventId:changes:)`, `deleteEvent(eventId:)`, `addLog(eventId:log:)` |
| Actions | `executeAction`, `executeStepAction` |
| Pipelines | `updateStepAsUser` |
| Profiles | `getProfiles(query:)`, `getProfile(userId:)`, `deleteProfile(userId:)` |
| Insights | `getInsights(query:)`, `getInsight(title:)`, `deleteInsight(title:)` |

Query parameters use `[String: String]`, including `page`, `limit`, `sortBy`, and API-specific filters. The configured project is injected automatically. Update fields and heterogeneous responses use `JSONObject` (`[String: AnyCodable]`) to preserve nested values, populated references and result details. Use `AnyCodable(NSNull())` to clear a badge in `updateEvent`.

`disableTracking()` suppresses telemetry writes, including API-token step updates; management reads and user-authorized actions remain available. Disabled creation returns an empty result without a synthetic event ID. Re-enable with `enableTracking()`.

Non-2xx responses throw `TracklyticHTTPError` with `statusCode`, raw `body`, and the API message in `localizedDescription`. Encoding and transport failures propagate without sending a silently empty body.

## Migration

- `userId` remains the canonical payload field; `user_id` is never emitted.
- Event `icon` was removed. Use `badge` and `logLevel`.
- Tags now accept arbitrary JSON using `AnyCodable`, including arrays, objects and null.
- `ActionComponent.action` is optional, allowing link components to omit it.
- `track` remains a Boolean success operation; use `createEvent`/`createPipeline` to receive pipeline IDs.

## Development

GitLab is the development source of truth. Branches and version tags are automatically mirrored to the public GitHub repository.

## Verification

```sh
swift test
swift build -c release
```

The test suite uses a mock `URLProtocol`, checks actual outgoing URLs, HTTP methods, credentials and JSON, and makes no production requests.
