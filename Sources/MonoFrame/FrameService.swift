import Foundation

// Networking against the MonoFrame Cloud Functions. Frame credentials live
// in FrameStore; registration happens inside the setup wizard.
enum FrameService {

    struct RegisterResponse: Codable {
        let frameId: String
        let token: String
    }

    struct Status {
        let lastSeen: Date?
        let hasImage: Bool
    }

    enum FrameError: LocalizedError {
        case badResponse(Int, String)

        var errorDescription: String? {
            switch self {
            case .badResponse(let code, let body):
                return "Server returned \(code): \(body)"
            }
        }
    }

    static let baseURL = "https://us-central1-monoframe-app.cloudfunctions.net"

    /// Mints a fresh {frameId, token} pair on the backend.
    static func register() async throws -> RegisterResponse {
        var req = URLRequest(url: URL(string: "\(baseURL)/registerFrame")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        let (data, resp) = try await URLSession.shared.data(for: req)
        try check(resp, data)
        return try JSONDecoder().decode(RegisterResponse.self, from: data)
    }

    static func upload(_ bitmap: Data, to frame: Frame) async throws {
        var req = URLRequest(url: URL(string: "\(baseURL)/uploadFrame?id=\(frame.frameId)")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("Bearer \(frame.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.httpBody = bitmap
        let (data, resp) = try await URLSession.shared.data(for: req)
        try check(resp, data)
    }

    static func status(of frame: Frame) async throws -> Status {
        var req = URLRequest(url: URL(string: "\(baseURL)/frameStatus?id=\(frame.frameId)")!)
        req.timeoutInterval = 15
        req.setValue("Bearer \(frame.token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try check(resp, data)

        struct Raw: Codable {
            let lastSeen: String?
            let hasImage: Bool
        }
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return Status(lastSeen: raw.lastSeen.flatMap { fmt.date(from: $0) },
                      hasImage: raw.hasImage)
    }

    /// URL the device firmware polls — shown in the advanced frame details.
    static func deviceURL(for frame: Frame) -> String {
        "\(baseURL)/getFrame?id=\(frame.frameId)"
    }

    private static func check(_ resp: URLResponse, _ body: Data) throws {
        guard let http = resp as? HTTPURLResponse else {
            throw FrameError.badResponse(-1, "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: body, encoding: .utf8)?.prefix(200) ?? "<binary>"
            throw FrameError.badResponse(http.statusCode, String(snippet))
        }
    }
}
