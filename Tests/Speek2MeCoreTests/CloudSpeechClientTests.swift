import Foundation
import Testing
@testable import Speek2MeCore

struct CloudSpeechClientTests {
    private func body(of request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func config(_ provider: VoiceProvider) -> CloudSpeechConfig {
        CloudSpeechConfig(voice: provider.defaultVoice, model: provider.defaultModel, region: provider.defaultRegion)
    }

    @Test func openAIRequest() throws {
        let request = try CloudSpeechClient.makeRequest(provider: .openAI, text: "hi", config: config(.openAI), apiKey: "sk-x")
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/audio/speech")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-x")
        let json = try body(of: request)
        #expect(json["model"] as? String == "gpt-4o-mini-tts")
        #expect(json["input"] as? String == "hi")
        #expect(json["voice"] as? String == "marin")
        #expect(json["response_format"] as? String == "mp3")
    }

    @Test func googleRequestAndBase64Response() throws {
        let request = try CloudSpeechClient.makeRequest(provider: .googleCloud, text: "hi", config: CloudSpeechConfig(voice: "nb-NO-Wavenet-A"), apiKey: "g")
        #expect(request.url?.absoluteString == "https://texttospeech.googleapis.com/v1/text:synthesize")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "g")
        let json = try body(of: request)
        #expect((json["input"] as? [String: Any])?["text"] as? String == "hi")
        #expect((json["voice"] as? [String: Any])?["languageCode"] as? String == "nb-NO")
        #expect((json["voice"] as? [String: Any])?["name"] as? String == "nb-NO-Wavenet-A")
        #expect((json["audioConfig"] as? [String: Any])?["audioEncoding"] as? String == "MP3")
        let audio = Data([1, 2, 3])
        let response = Data(#"{"audioContent":"\#(audio.base64EncodedString())"}"#.utf8)
        #expect(try CloudSpeechClient.parseResponse(provider: .googleCloud, data: response, status: 200) == audio)
        #expect(throws: SpeakerError.badAudio) { try CloudSpeechClient.parseResponse(provider: .googleCloud, data: Data("{}".utf8), status: 200) }
    }

    @Test func azureRequestIsSSMLWithRegion() throws {
        let request = try CloudSpeechClient.makeRequest(provider: .azure, text: "A & B <c>", config: config(.azure), apiKey: "az")
        #expect(request.url?.absoluteString == "https://norwayeast.tts.speech.microsoft.com/cognitiveservices/v1")
        #expect(request.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key") == "az")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/ssml+xml")
        #expect(request.value(forHTTPHeaderField: "X-Microsoft-OutputFormat") == "audio-24khz-48kbitrate-mono-mp3")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Speek2Me")
        let ssml = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(ssml == "<speak version='1.0' xml:lang='en-US'><voice name='en-US-JennyNeural'>A &amp; B &lt;c&gt;</voice></speak>")
        #expect(throws: SpeakerError.self) {
            try CloudSpeechClient.makeRequest(provider: .azure, text: "x", config: CloudSpeechConfig(voice: "v", region: ""), apiKey: "k")
        }
    }

    @Test func deepgramRequest() throws {
        let request = try CloudSpeechClient.makeRequest(provider: .deepgram, text: "hi", config: config(.deepgram), apiKey: "dg")
        #expect(request.url?.absoluteString == "https://api.deepgram.com/v1/speak?model=aura-2-thalia-en&encoding=mp3")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Token dg")
        #expect(try body(of: request)["text"] as? String == "hi")
    }

    @Test func cartesiaRequest() throws {
        let request = try CloudSpeechClient.makeRequest(provider: .cartesia, text: "hi", config: config(.cartesia), apiKey: "sk_car_1")
        #expect(request.url?.absoluteString == "https://api.cartesia.ai/tts/bytes")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk_car_1")
        #expect(request.value(forHTTPHeaderField: "Cartesia-Version") == CloudSpeechClient.cartesiaVersion)
        let json = try body(of: request)
        #expect(json["model_id"] as? String == "sonic-3.6")
        #expect(json["transcript"] as? String == "hi")
        #expect((json["voice"] as? [String: Any])?["id"] as? String == VoiceProvider.cartesia.defaultVoice)
        let format = try #require(json["output_format"] as? [String: Any])
        #expect(format["container"] as? String == "mp3")
        #expect(format["sample_rate"] as? Int == 44_100)
        #expect(format["bit_rate"] as? Int == 128_000)
    }

    @Test func elevenLabsRoutesToItsOwnClient() throws {
        let request = try CloudSpeechClient.makeRequest(provider: .elevenLabs, text: "hi", config: config(.elevenLabs), apiKey: "k")
        #expect(request.url?.absoluteString.hasPrefix("https://api.elevenlabs.io/v1/text-to-speech/") == true)
        #expect(request.value(forHTTPHeaderField: "xi-api-key") == "k")
    }

    @Test func textIsCappedPerProvider() throws {
        let long = String(repeating: "a", count: 10_000)
        let openAI = try CloudSpeechClient.makeRequest(provider: .openAI, text: long, config: config(.openAI), apiKey: "k")
        #expect((try body(of: openAI)["input"] as? String)?.count == 4_096)
        let deepgram = try CloudSpeechClient.makeRequest(provider: .deepgram, text: long, config: config(.deepgram), apiKey: "k")
        #expect((try body(of: deepgram)["text"] as? String)?.count == 2_000)
    }

    @Test func errorsMapAcrossProviderShapes() {
        #expect(throws: SpeakerError.invalidAPIKey("bad key")) {
            try CloudSpeechClient.parseResponse(provider: .openAI, data: Data(#"{"error":{"message":"bad key","type":"invalid_request_error"}}"#.utf8), status: 401)
        }
        #expect(throws: SpeakerError.quotaOrRateLimit("slow down")) {
            try CloudSpeechClient.parseResponse(provider: .deepgram, data: Data(#"{"err_code":"x","err_msg":"slow down"}"#.utf8), status: 429)
        }
        #expect(throws: SpeakerError.http(status: 400, message: "Bad request")) {
            try CloudSpeechClient.parseResponse(provider: .azure, data: Data("Bad request".utf8), status: 400)
        }
        #expect(throws: SpeakerError.badAudio) { try CloudSpeechClient.parseResponse(provider: .cartesia, data: Data(), status: 200) }
        #expect(throws: SpeakerError.engine("Apple (on this Mac) is not a cloud provider")) {
            try CloudSpeechClient.makeRequest(provider: .apple, text: "x", config: CloudSpeechConfig(voice: ""), apiKey: "k")
        }
    }

    @Test func providerMetadataIsConsistent() {
        for provider in VoiceProvider.allCases {
            #expect(provider.maxCharacters > 0)
            #expect(provider.needsKey == provider.fields.contains(.key))
            if provider.needsKey { #expect(provider.keyURL != nil, "\(provider)") }
            if provider.fields.contains(.model) { #expect(!provider.defaultModel.isEmpty, "\(provider)") }
            if provider.fields.contains(.region) { #expect(!provider.defaultRegion.isEmpty, "\(provider)") }
        }
    }
}
