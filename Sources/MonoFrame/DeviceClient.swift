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

    // Streams a new firmware image to the frame's /update endpoint. Slow
    // (~1.2 MB over the SoftAP) — the frame reboots itself on success.
    static func updateFirmware(_ image: Data) async throws {
        let boundary = "monoframe-\(UUID().uuidString)"
        var req = URLRequest(url: URL(string: "\(host)/update")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("multipart/form-data; boundary=\(boundary)",
                     forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append(Data("""
        --\(boundary)\r
        Content-Disposition: form-data; name="firmware"; filename="firmware.bin"\r
        Content-Type: application/octet-stream\r
        \r\n
        """.utf8))
        body.append(image)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        let (data, resp) = try await session.upload(for: req, from: body)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "DeviceClient", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Frame rejected the update: \(text)",
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
    // Frames on firmware 2.4.0+ protect the setup hotspot with a WiFi code
    // shown on their screen; older frames broadcast an open network.
    static func joinFrameHotspot(code: String = "") async throws {
        let config = code.isEmpty
            ? NEHotspotConfiguration(ssidPrefix: "MonoFrame-")
            : NEHotspotConfiguration(ssidPrefix: "MonoFrame-", passphrase: code, isWEP: false)
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
