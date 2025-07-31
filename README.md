<div align="center">
    <h1>Tracklytic Swift</h1>
    <p>Track your project events and get insights.</p>
    <br>
</div>


## Installation

### Swift Package Manager

- File > Swift Packages > Add Package Dependency
- Add `https://github.com/scalerit/tracklytic-swift.git`
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

