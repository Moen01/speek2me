import Foundation

/// The cloud voice: fetches MP3 audio for the text and plays it.
public struct ElevenLabsSpeaker: Speaker {
    private let session: URLSession
    private let playback: AudioPlayback
    private let apiKey: @Sendable () -> String?
    private let voiceID: @Sendable () -> String
    private let modelID: @Sendable () -> String
    private let timeout: Duration

    public init(
        session: URLSession = .shared,
        playback: AudioPlayback,
        apiKey: @escaping @Sendable () -> String?,
        voiceID: @escaping @Sendable () -> String,
        modelID: @escaping @Sendable () -> String,
        timeout: Duration = .seconds(10)
    ) {
        self.session = session
        self.playback = playback
        self.apiKey = apiKey
        self.voiceID = voiceID
        self.modelID = modelID
        self.timeout = timeout
    }

    public func speak(_ text: String) async throws {
        guard let key = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw SpeakerError.missingAPIKey
        }
        var request = try ElevenLabsClient.makeSpeechRequest(text: text, voiceID: voiceID(), modelID: modelID(), apiKey: key)
        request.timeoutInterval = TimeInterval(timeout.components.seconds)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw SpeakerError.timedOut
        }
        let audio = try ElevenLabsClient.parseSpeechResponse(data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        try await playback.play(audio)
    }

    public func stop() async {
        playback.stop()
    }
}
