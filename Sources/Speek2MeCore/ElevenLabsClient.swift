import Foundation

public struct ElevenLabsVoice: Codable, Equatable, Identifiable, Sendable {
    public let voiceID: String
    public let name: String
    public let category: String?

    public var id: String { voiceID }

    enum CodingKeys: String, CodingKey {
        case voiceID = "voice_id"
        case name
        case category
    }

    public init(voiceID: String, name: String, category: String?) {
        self.voiceID = voiceID
        self.name = name
        self.category = category
    }
}

/// Request builders and response parsers for the three ElevenLabs endpoints Speek2Me uses.
public enum ElevenLabsClient {
    public static let baseURL = URL(string: "https://api.elevenlabs.io")!
    public static let defaultModelID = "eleven_flash_v2_5"
    /// "Rachel", a premade voice every account has.
    public static let defaultVoiceID = "21m00Tcm4TlvDq8ikWAM"
    /// Announcements are short; anything longer is a runaway raw message.
    public static let maxCharacters = 2_500

    struct SpeechBody: Encodable {
        let text: String
        let model_id: String
    }

    struct VoicesBody: Decodable {
        let voices: [ElevenLabsVoice]
    }

    public static func makeSpeechRequest(text: String, voiceID: String, modelID: String, apiKey: String) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/text-to-speech/\(voiceID)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "output_format", value: "mp3_44100_128")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(SpeechBody(text: String(text.prefix(maxCharacters)), model_id: modelID))
        return request
    }

    public static func makeVoicesRequest(apiKey: String) -> URLRequest {
        get("v1/voices", apiKey: apiKey)
    }

    public static func makeVerifyRequest(apiKey: String) -> URLRequest {
        get("v1/user", apiKey: apiKey)
    }

    private static func get(_ path: String, apiKey: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        return request
    }

    public static func parseSpeechResponse(data: Data, status: Int) throws -> Data {
        guard (200..<300).contains(status) else { throw mapError(status: status, data: data) }
        guard !data.isEmpty else { throw SpeakerError.badAudio }
        return data
    }

    public static func parseVoicesResponse(data: Data, status: Int) throws -> [ElevenLabsVoice] {
        guard (200..<300).contains(status) else { throw mapError(status: status, data: data) }
        do {
            return try JSONDecoder().decode(VoicesBody.self, from: data).voices
        } catch {
            throw SpeakerError.http(status: status, message: "unexpected voices response")
        }
    }

    public static func listVoices(apiKey: String, session: URLSession = .shared) async throws -> [ElevenLabsVoice] {
        let (data, response) = try await session.data(for: makeVoicesRequest(apiKey: apiKey))
        return try parseVoicesResponse(data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Throws a `SpeakerError` when the key is rejected; returns quietly when it works.
    public static func verify(apiKey: String, session: URLSession = .shared) async throws {
        let (data, response) = try await session.data(for: makeVerifyRequest(apiKey: apiKey))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw mapError(status: status, data: data) }
    }

    /// ElevenLabs errors come as `{"detail":{"status":…,"message":…}}`, `{"detail":"…"}`, or plain text.
    static func mapError(status: Int, data: Data) -> SpeakerError {
        let message: String
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let detail = object["detail"] {
            if let detail = detail as? [String: Any], let text = detail["message"] as? String {
                message = text
            } else if let text = detail as? String {
                message = text
            } else {
                message = String(decoding: data.prefix(300), as: UTF8.self)
            }
        } else {
            message = String(decoding: data.prefix(300), as: UTF8.self)
        }
        switch status {
        case 401, 403: return .invalidAPIKey(message)
        case 402, 429: return .quotaOrRateLimit(message)
        default: return .http(status: status, message: message)
        }
    }
}
