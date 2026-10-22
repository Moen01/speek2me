import Foundation

/// Where the spoken audio comes from. Every provider except Apple and Piper is a cloud API.
public enum VoiceProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case elevenLabs
    case apple
    case openAI
    case googleCloud
    case azure
    case deepgram
    case cartesia
    case piper

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .elevenLabs: "ElevenLabs"
        case .apple: "Apple (on this Mac)"
        case .openAI: "OpenAI"
        case .googleCloud: "Google Cloud Text-to-Speech"
        case .azure: "Azure Speech"
        case .deepgram: "Deepgram Aura"
        case .cartesia: "Cartesia Sonic"
        case .piper: "Piper (local, open source)"
        }
    }

    /// Which settings the provider uses. `key` means a secret in the Keychain.
    public enum Field: Sendable {
        case key, voice, model, region, executable, modelFile
    }

    public var fields: [Field] {
        switch self {
        case .elevenLabs: [.key, .voice, .model]
        case .apple: [.voice]
        case .openAI: [.key, .voice, .model]
        case .googleCloud: [.key, .voice]
        case .azure: [.key, .voice, .region]
        case .deepgram: [.key, .voice]
        case .cartesia: [.key, .voice, .model]
        case .piper: [.executable, .modelFile]
        }
    }

    public var needsKey: Bool { fields.contains(.key) }
    public var isCloud: Bool { needsKey }

    /// The voice (or voice id, or Deepgram model) used until the user picks another.
    public var defaultVoice: String {
        switch self {
        case .elevenLabs: "21m00Tcm4TlvDq8ikWAM"              // Rachel
        case .apple: ""                                       // system default
        case .openAI: "marin"
        case .googleCloud: "en-US-Chirp3-HD-Aoede"
        case .azure: "en-US-JennyNeural"
        case .deepgram: "aura-2-thalia-en"
        case .cartesia: "db6b0ed5-d5d3-463d-ae85-518a07d3c2b4" // the id used in Cartesia's docs
        case .piper: ""
        }
    }

    public var defaultModel: String {
        switch self {
        case .elevenLabs: "eleven_flash_v2_5"
        case .openAI: "gpt-4o-mini-tts"
        case .cartesia: "sonic-3.6"
        default: ""
        }
    }

    /// Azure's endpoint is per region; Norway East is the nearest one for this user.
    public var defaultRegion: String { self == .azure ? "norwayeast" : "" }

    public var voiceHint: String {
        switch self {
        case .elevenLabs: "Voice id (pick from the list once a key is saved)"
        case .apple: "Apple voice"
        case .openAI: "alloy, ash, ballad, coral, echo, fable, onyx, nova, sage, shimmer, verse, marin, cedar"
        case .googleCloud: "Voice name, e.g. en-US-Chirp3-HD-Aoede or nb-NO-Wavenet-A"
        case .azure: "Voice name, e.g. en-US-JennyNeural or nb-NO-FinnNeural"
        case .deepgram: "Model, e.g. aura-2-thalia-en, aura-2-apollo-en"
        case .cartesia: "Voice id from the Cartesia voice library"
        case .piper: ""
        }
    }

    /// The provider's own input cap; OpenAI documents 4,096 characters, Deepgram 2,000.
    public var maxCharacters: Int {
        switch self {
        case .openAI: 4_096
        case .deepgram: 2_000
        default: 2_500
        }
    }

    public var keyURL: URL? {
        switch self {
        case .elevenLabs: URL(string: "https://elevenlabs.io/app/settings/api-keys")
        case .openAI: URL(string: "https://platform.openai.com/api-keys")
        case .googleCloud: URL(string: "https://console.cloud.google.com/apis/credentials")
        case .azure: URL(string: "https://portal.azure.com/#view/Microsoft_Azure_ProjectOxford/CognitiveServicesHub/~/SpeechServices")
        case .deepgram: URL(string: "https://console.deepgram.com/")
        case .cartesia: URL(string: "https://play.cartesia.ai/keys")
        case .apple, .piper: nil
        }
    }

    public var note: String {
        switch self {
        case .elevenLabs: "Best quality. Each announcement is billed to your key."
        case .apple: "Free and offline. Download a Premium voice in System Settings for a much better one."
        case .openAI: "gpt-4o-mini-tts. Billed per character to your OpenAI key."
        case .googleCloud: "Enable the Text-to-Speech API on the project and create an API key restricted to it."
        case .azure: "Create a Speech resource; use its key and region."
        case .deepgram: "Aura-2 voices. Billed per character."
        case .cartesia: "Sonic voices. Billed per character."
        case .piper: "Runs on this Mac. Install with `pip install piper-tts` and download a voice (.onnx + .json) from the Piper voices collection."
        }
    }
}
