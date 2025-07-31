import Combine
import Foundation

/// Tracklytic Client
public class TracklyticClient {
    
    private let dataClient: TracklyticDataClientProvider
    private let project: String
    private let token: String
    private var disabled = false
    
    private lazy var jsonEncoder = JSONEncoder()
    
    init(
        dataClient: TracklyticDataClientProvider,
        project: String,
        token: String
    ) {
        self.dataClient = dataClient
        self.project = project
        self.token = token
    }
    
    /// Construct a new Tracklytic instance
    /// - Parameters:
    /// - project: Your project slug
    /// - token: Your API token. See docs.tracklytic.com for details
    public init(
        project: String,
        token: String
    ) {
        self.project = project
        self.token = token
        self.dataClient = TracklyticDataClient()
    }
    
    /// Disable tracking for this instance
    /// (this is useful for development)
    public func disableTracking() {
        self.disabled = true
    }
    
    /// Enable tracking for this instance
    /// (this is useful for development)
    public func enableTracking() {
        self.disabled = false
    }
    
    /// Get project name
    /// - Returns: project name
    public func getProject() -> String {
        return self.project
    }
    
    private func createAuthorizationHeader() -> String {
        "Bearer \(token)"
    }
    
    private func request(options: TrackOptions) -> URLRequest {
        var request = URLRequest(url: URL(string: Constants.tracklyticEndpoint)!)
        
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = [
            "Content-Type": "application/json",
            "Authorization": createAuthorizationHeader()
        ]
        
        var options = options
        options.project = project
        
        request.httpBody = try? jsonEncoder.encode(options)
        
        return request
    }
    
    /// Publish a new event to Tracklytic
    /// - Parameter options
    /// - Returns: true when successfully published
    @available(iOS 15.0, *)
    @available(macOS 12.0, *)
    @available(tvOS 15.0, *)
    @available(watchOS 8.0, *)
    @discardableResult
    public func track(options: TrackOptions) async throws -> Bool {
        if (disabled) { return true }
        return try await dataClient.data(for: request(options: options))
    }
    
    /// Publish a new event to Tracklytic
    /// - Parameter options
    /// - Returns: Combine `Publisher`
    public func track(options: TrackOptions) -> AnyPublisher<Bool, Error> {
        if (disabled) { 
            return Just(true)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
        return dataClient.dataTaskPublisher(for: request(options: options))
    }
} 