import Foundation

/// The local open-source voice: runs the user's `piper` install with a downloaded voice model.
/// Text goes in on stdin, a WAV file comes out, the app plays it. Nothing leaves the Mac.
public struct PiperSpeaker: Speaker {
    public let executable: URL
    public let model: URL
    private let playback: AudioPlayback

    public init(executable: URL, model: URL, playback: AudioPlayback) {
        self.executable = executable
        self.model = model
        self.playback = playback
    }

    /// Both the original C++ CLI and the Python `piper-tts` CLI accept these flags.
    public static func arguments(model: URL, output: URL) -> [String] {
        ["--model", model.path, "--output_file", output.path]
    }

    public func speak(_ text: String) async throws {
        try Task.checkCancellation()
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("speek2me-piper-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: output) }
        // One utterance per line; keep it to one line so piper makes one file.
        let line = text.replacingOccurrences(of: "\n", with: " ") + "\n"
        do {
            _ = try await ProcessRunner.run(
                executable, arguments: Self.arguments(model: model, output: output),
                stdin: Data(line.utf8), environment: ProcessRunner.environment(for: executable))
        } catch ProcessError.failed(let message) {
            throw SpeakerError.engine(message)
        }
        guard let audio = try? Data(contentsOf: output), !audio.isEmpty else {
            throw SpeakerError.engine("piper produced no audio")
        }
        try await playback.play(audio)
    }

    public func stop() async {
        playback.stop()
    }
}
