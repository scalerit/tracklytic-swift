<div align="center">
    <h1>Tracklytic Swift</h1>
    <p>Track your project events and get insights.</p>
    <a href="https://discord.gg/dY3pRxgWua"><img src="https://img.shields.io/discord/922560704454750245?color=%237289DA&label=Discord" alt="Discord"></a>
    <a href="https://docs.tracklytic.com"><img src="https://img.shields.io/badge/Docs-Tracklytic" alt="Documentation"></a>
    <br>
    <br>
</div>


## Installation

### Swift Package Manager

- File > Swift Packages > Add Package Dependency
- Add `https://github.com/Camji55/tracklytic-swift.git`
- Select "Up to Next Major" with "1.0.0"

## Usage

### Import Library

```swift
import Tracklytic
```

### Initialize Client

```swift
let tracklytic = TracklyticClient(
    project: "my-sass",
    token: "YOUR_API_TOKEN"
)
```

### Track Event

#### `async/await`

```swift
let success = try await tracklytic.track(
    options: TrackOptions(
        channel: "507f1f77bcf86cd799439013",
        event: "User Joined",
        description: "New user signed up",
        icon: "🎉",
        notify: true
    )
)
```

#### Combine

```swift
tracklytic.track(
    options: TrackOptions(
        channel: "507f1f77bcf86cd799439013",
        event: "User Joined",
        description: "New user signed up",
        icon: "🎉",
        notify: true
    )
)
.sink(
    receiveCompletion: { _ in },
    receiveValue: { _ in }
)
.store(in: &cancellables)
```

