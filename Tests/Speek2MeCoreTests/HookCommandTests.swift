import Foundation
import Testing
@testable import Speek2MeCore

struct HookCommandTests {
    @Test func commandQuotesPathAndParsesBack() {
        let bundle = URL(fileURLWithPath: "/Applications/Speek2Me.app")
        let command = HookCommand.command(bundleURL: bundle, tool: "claude")
        #expect(command == "\"/Applications/Speek2Me.app/Contents/MacOS/speek2me-hook\" claude")
        #expect(HookCommand.executablePath(in: command) == "/Applications/Speek2Me.app/Contents/MacOS/speek2me-hook")
        #expect(HookCommand.executablePath(in: "/x/y hook") == "/x/y")
        #expect(HookCommand.isHealthy("\"/Applications/Nope-\(UUID().uuidString).app/Contents/MacOS/speek2me-hook\" claude") == false)
        #expect(HookCommand.isHealthy("\"/bin/ls\" claude"))
    }
}
