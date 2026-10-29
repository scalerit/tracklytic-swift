import Foundation

public struct TracklyticHTTPError: Error, LocalizedError {
  public let statusCode: Int
  public let body: Data
  public var errorDescription: String? {
    let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    return payload?["message"] as? String ?? "Tracklytic request failed (HTTP \(statusCode))"
  }
}

func validateResponse(data: Data, response: URLResponse) throws -> Data {
  guard let http = response as? HTTPURLResponse else { throw URLError(.cannotParseResponse) }
  guard (200..<300).contains(http.statusCode) else {
    throw TracklyticHTTPError(statusCode: http.statusCode, body: data)
  }
  return data.isEmpty ? Data("{}".utf8) : data
}
