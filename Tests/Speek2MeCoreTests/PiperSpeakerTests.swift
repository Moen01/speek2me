import Foundation
import Testing
@testable import Speek2MeCore

struct PiperSpeakerTests {
    private func fakePiper(_ body: String) throws -> (script: URL, dir: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("speek2me-piper-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("piper")
        try ("#!/bin/sh\n" + body).write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (script, dir)
    }

    @Test func argumentsNameModelAndOutput() {
        let args = PiperSpeaker.arguments(model: URL(fileURLWithPath: "/v/en.onnx"), output: URL(fileURLWithPath: "/t/o.wav"))
        #expect(args == ["--model", "/v/en.onnx", "--output_file", "/t/o.wav"])
    }

    @Test func speaksWhatTheEngineWrites() async throws {
        // The fake "piper" copies a system sound to the requested output file and records the text it got.
        let (script, dir) = try fakePiper("""
        out=""
        while [ $# -gt 0 ]; do [ "$1" = "--output_file" ] && out="$2"; shift; done
        cat > "$(dirname "$0")/heard.txt"
        cp /System/Library/Sounds/Tink.aiff "$out"
        """)
        defer { try? FileManager.default.removeItem(at: dir) }
        let speaker = PiperSpeaker(executable: script, model: URL(fileURLWithPath: "/v/en.onnx"), playback: AudioPlayback())
        try await speaker.speak("hello\nthere")
        #expect(try String(contentsOf: dir.appendingPathComponent("heard.txt"), encoding: .utf8) == "hello there\n")
    }

    @Test func engineFailureIsReported() async throws {
        let (script, dir) = try fakePiper("cat > /dev/null\necho 'no such model' >&2\nexit 1\n")
        defer { try? FileManager.default.removeItem(at: dir) }
        let speaker = PiperSpeaker(executable: script, model: URL(fileURLWithPath: "/v/en.onnx"), playback: AudioPlayback())
        await #expect(throws: SpeakerError.engine("no such model\n")) { try await speaker.speak("hi") }
        let (silent, dir2) = try fakePiper("cat > /dev/null\n")
        defer { try? FileManager.default.removeItem(at: dir2) }
        await #expect(throws: SpeakerError.engine("piper produced no audio")) {
            try await PiperSpeaker(executable: silent, model: URL(fileURLWithPath: "/v/en.onnx"), playback: AudioPlayback()).speak("hi")
        }
    }
}
