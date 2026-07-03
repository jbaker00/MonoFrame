import Foundation
import NetworkExtension

// Talks to a frame in setup mode over its SoftAP (192.168.4.1). Uses a
// cellular-disabled session so requests go out the WiFi interface even
// though the frame's hotspot has no internet.
enum DeviceClient {

    struct Info: Codable {
        let model: String
        let mac: String
        let fw: String
        let name: String
        let provisioned: Bool
    }

    static let host = "http://192.168.4.1"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.allowsCellularAccess = false
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 5
        return URLSession(configuration: config)
    }()

    static func info() async throws -> Info {
        let (data, resp) = try await session.data(from: URL(string: "\(host)/info")!)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Info.self, from: data)
    }

    static func provision(ssid: String, pass: String,
                          frameId: String, token: String) async throws {
        var req = URLRequest(url: URL(string: "\(host)/provision")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = formEncode([
            "ssid": ssid, "pass": pass, "frameId": frameId, "token": token,
        ])
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "DeviceClient", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Frame rejected setup: \(body)",
            ])
        }
    }

    private static func formEncode(_ params: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params
            .map { key, value in
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
                return "\(key)=\(v)"
            }
            .joined(separator: "&")
            .data(using: .utf8)!
    }
}

// Joins the frame's "MonoFrame-…" hotspot. joinOnce keeps iOS from
// persisting the configuration, so the phone drops back to the home network
// once the frame reboots and the AP disappears.
enum HotspotJoiner {
    static func joinFrameHotspot() async throws {
        let config = NEHotspotConfiguration(ssidPrefix: "MonoFrame-")
        config.joinOnce = true
        do {
            try await NEHotspotConfigurationManager.shared.apply(config)
        } catch {
            let nsError = error as NSError
            // "already associated" is success for our purposes.
            if nsError.domain == NEHotspotConfigurationErrorDomain,
               nsError.code == NEHotspotConfigurationError.alreadyAssociated.rawValue {
                return
            }
            throw error
        }
    }
}
