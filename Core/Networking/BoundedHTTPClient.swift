import Foundation

enum HTTPClientError: LocalizedError {
    case invalidResponse
    case responseTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "服务器返回异常"
        case .responseTooLarge(let bytes):
            "响应超过 \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))"
        }
    }
}

protocol HTTPDataLoading: Sendable {
    func data(for request: URLRequest, maximumBytes: Int,
              additionalValidStatusCodes: Set<Int>) async throws -> (Data, HTTPURLResponse)
}

extension HTTPDataLoading {
    func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, HTTPURLResponse) {
        try await data(for: request, maximumBytes: maximumBytes, additionalValidStatusCodes: [])
    }
}

struct BoundedHTTPClient: HTTPDataLoading {
    func data(for request: URLRequest, maximumBytes: Int,
              additionalValidStatusCodes: Set<Int> = []) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode || additionalValidStatusCodes.contains(http.statusCode) else {
            throw HTTPClientError.invalidResponse
        }
        if response.expectedContentLength > Int64(maximumBytes) {
            throw HTTPClientError.responseTooLarge(maximumBytes)
        }

        var data = Data()
        data.reserveCapacity(min(maximumBytes, max(0, Int(response.expectedContentLength))))
        for try await byte in bytes {
            guard data.count < maximumBytes else {
                throw HTTPClientError.responseTooLarge(maximumBytes)
            }
            data.append(byte)
        }
        return (data, http)
    }
}
