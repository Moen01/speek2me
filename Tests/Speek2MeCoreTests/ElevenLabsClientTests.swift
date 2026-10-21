import Foundation
import Testing
@testable import Speek2MeCore

struct ElevenLabsClientTests {
    private func body(of request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func speechRequestShape() throws {
        let request = try ElevenLabsClient.makeSpeechRequest(text: "hi", voiceID: "v1", modelID: "eleven_flash_v2_5", apiKey: "k")
        #expect(request.url?.absoluteString == "https://api.elevenlabs.io/v1/text-to-speech/v1?output_format=mp3_44100_128")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "xi-api-key") == "k")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let json = try body(of: request)
        #expect(json["text"] as? String == "hi")
        #expect(json["model_id"] as? String == "eleven_flash_v2_5")
    }

    @Test func truncatesLongText() throws {
        let request = try ElevenLabsClient.makeSpeechRequest(text: String(repeating: "a", count: 10_000), voiceID: "v", modelID: "m", apiKey: "k")
        #expect((try body(of: request)["text"] as? String)?.count == ElevenLabsClient.maxCharacters)
    }

    @Test func voicesAndVerifyRequests() {
        let voices = ElevenLabsClient.makeVoicesRequest(apiKey: "k")
        #expect(voices.url?.absoluteString == "https://api.elevenlabs.io/v1/voices")
        #expect(voices.value(forHTTPHeaderField: "xi-api-key") == "k")
        #expect(ElevenLabsClient.makeVerifyRequest(apiKey: "k").url?.absoluteString == "https://api.elevenlabs.io/v1/user")
    }

    @Test func errorsMapByStatus() throws {
        let unauthorized = Data(#"{"detail":{"status":"invalid_api_key","message":"bad key"}}"#.utf8)
        #expect(throws: SpeakerError.invalidAPIKey("bad key")) { try ElevenLabsClient.parseSpeechResponse(data: unauthorized, status: 401) }
        let limited = Data(#"{"detail":"too many"}"#.utf8)
        #expect(throws: SpeakerError.quotaOrRateLimit("too many")) { try ElevenLabsClient.parseSpeechResponse(data: limited, status: 429) }
        #expect(throws: SpeakerError.http(status: 500, message: "boom")) { try ElevenLabsClient.parseSpeechResponse(data: Data("boom".utf8), status: 500) }
        #expect(throws: SpeakerError.badAudio) { try ElevenLabsClient.parseSpeechResponse(data: Data(), status: 200) }
        #expect(try ElevenLabsClient.parseSpeechResponse(data: Data("abc".utf8), status: 200) == Data("abc".utf8))
    }

    @Test func parsesVoices() throws {
        let data = Data(#"{"voices":[{"voice_id":"v","name":"Rachel","category":"premade","labels":{}}]}"#.utf8)
        #expect(try ElevenLabsClient.parseVoicesResponse(data: data, status: 200) == [ElevenLabsVoice(voiceID: "v", name: "Rachel", category: "premade")])
        #expect(throws: SpeakerError.invalidAPIKey("no")) { try ElevenLabsClient.parseVoicesResponse(data: Data(#"{"detail":"no"}"#.utf8), status: 401) }
    }
}
