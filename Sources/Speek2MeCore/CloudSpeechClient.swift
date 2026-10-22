import Foundation

/// What a cloud voice needs besides the key: a voice (or voice id), sometimes a model, for Azure a region.
public struct CloudSpeechConfig: Sendable, Equatable {
    public var voice: String
    public var model: String
    public var region: String

    public init(voice: String, model: String = "", region: String = "") {
        self.voice = voice
        self.model = model
        self.region = region
    }
}

/// Request builders and response parsers for every cloud voice provider. All return MP3 bytes.
public enum CloudSpeechClient {
    public static let cartesiaVersion = "2026-08-14"

    public static func makeRequest(provider: VoiceProvider, text: String, config: CloudSpeechConfig, apiKey: String) throws -> URLRequest {
        let text = String(text.prefix(provider.maxCharacters))
        switch provider {
        case .elevenLabs:
            return try ElevenLabsClient.makeSpeechRequest(text: text, voiceID: config.voice, modelID: config.model, apiKey: apiKey)

        case .openAI:
            var request = post(URL(string: "https://api.openai.com/v1/audio/speech")!)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = try json(["model": config.model, "input": text, "voice": config.voice, "response_format": "mp3"])
            return request

        case .googleCloud:
            var request = post(URL(string: "https://texttospeech.googleapis.com/v1/text:synthesize")!)
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            request.httpBody = try json([
                "input": ["text": text],
                "voice": ["languageCode": languageCode(of: config.voice), "name": config.voice],
                "audioConfig": ["audioEncoding": "MP3"],
            ])
            return request

        case .azure:
            let region = config.region.trimmingCharacters(in: .whitespaces)
            guard let url = URL(string: "https://\(region).tts.speech.microsoft.com/cognitiveservices/v1"), !region.isEmpty else {
                throw SpeakerError.http(status: 0, message: "Azure region is missing")
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
            request.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
            request.setValue("audio-24khz-48kbitrate-mono-mp3", forHTTPHeaderField: "X-Microsoft-OutputFormat")
            request.setValue("Speek2Me", forHTTPHeaderField: "User-Agent")
            request.httpBody = Data(ssml(text: text, voice: config.voice).utf8)
            return request

        case .deepgram:
            var components = URLComponents(string: "https://api.deepgram.com/v1/speak")!
            components.queryItems = [URLQueryItem(name: "model", value: config.voice), URLQueryItem(name: "encoding", value: "mp3")]
            var request = post(components.url!)
            request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = try json(["text": text])
            return request

        case .cartesia:
            var request = post(URL(string: "https://api.cartesia.ai/tts/bytes")!)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(cartesiaVersion, forHTTPHeaderField: "Cartesia-Version")
            request.httpBody = try json([
                "model_id": config.model,
                "transcript": text,
                "voice": ["id": config.voice],
                "output_format": ["container": "mp3", "sample_rate": 44_100, "bit_rate": 128_000],
            ])
            return request

        case .apple, .piper:
            throw SpeakerError.engine("\(provider.displayName) is not a cloud provider")
        }
    }

    /// MP3 bytes on success. Google wraps them in JSON as base64; the others return them raw.
    public static func parseResponse(provider: VoiceProvider, data: Data, status: Int) throws -> Data {
        guard (200..<300).contains(status) else { throw mapError(status: status, data: data) }
        switch provider {
        case .googleCloud:
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let base64 = object["audioContent"] as? String,
                  let audio = Data(base64Encoded: base64), !audio.isEmpty else { throw SpeakerError.badAudio }
            return audio
        default:
            guard !data.isEmpty else { throw SpeakerError.badAudio }
            return data
        }
    }

    /// Each provider has its own error JSON; look for the common message fields, else the body.
    static func mapError(status: Int, data: Data) -> SpeakerError {
        var message = String(decoding: data.prefix(300), as: UTF8.self)
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any], let text = error["message"] as? String {
                message = text
            } else if let text = object["error"] as? String {
                message = text
            } else if let text = object["message"] as? String {
                message = text
            } else if let text = object["err_msg"] as? String {
                message = text
            } else if let detail = object["detail"] as? [String: Any], let text = detail["message"] as? String {
                message = text
            } else if let text = object["detail"] as? String {
                message = text
            }
        }
        switch status {
        case 401, 403: return .invalidAPIKey(message)
        case 402, 429: return .quotaOrRateLimit(message)
        default: return .http(status: status, message: message)
        }
    }

    // MARK: - Helpers

    /// "en-US-JennyNeural" and "nb-NO-Wavenet-A" both start with their language code.
    static func languageCode(of voice: String) -> String {
        let parts = voice.split(separator: "-")
        return parts.count >= 2 ? "\(parts[0])-\(parts[1])" : "en-US"
    }

    static func ssml(text: String, voice: String) -> String {
        let language = languageCode(of: voice)
        return "<speak version='1.0' xml:lang='\(language)'><voice name='\(escape(voice))'>\(escape(text))</voice></speak>"
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func post(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        return request
    }

    private static func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
