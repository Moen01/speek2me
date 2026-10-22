import Foundation

/// A cloud voice: fetches MP3 audio for the text from the selected provider and plays it.
public struct CloudSpeaker: Speaker {
    private let provider: VoiceProvider
    private let session: URLSession
    private let playback: AudioPlayback
    private let apiKey: @Sendable () -> String?
    private let config: @Sendable () -> CloudSpeechConfig
    private let timeout: Duration

    public init(
        provider: VoiceProvider,
        session: URLSession = .shared,
        playback: AudioPlayback,
        apiKey: @escaping @Sendable () -> String?,
        config: @escaping @Sendable () -> CloudSpeechConfig,
        timeout: Duration = .seconds(10)
    ) {
        self.provider = provider
        self.session = session
        self.playback = playback
        self.apiKey = apiKey
        self.config = config
        self.timeout = timeout
    }

    public func speak(_ text: String) async throws {
        guard let key = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw SpeakerError.missingAPIKey
        }
        var request = try CloudSpeechClient.makeRequest(provider: provider, text: text, config: config(), apiKey: key)
        request.timeoutInterval = TimeInterval(timeout.components.seconds)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw SpeakerError.timedOut
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }
        let audio = try CloudSpeechClient.parseResponse(provider: provider, data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        try await playback.play(audio)
    }

    public func stop() async {
        playback.stop()
    }
}
