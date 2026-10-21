import Foundation
import Speek2MeCore

// The tool writes its JSON and closes stdin; read it all, drop one file in the inbox, leave.
let input = FileHandle.standardInput.readDataToEndOfFile()
let tool = CommandLine.arguments.dropFirst().first ?? ""
exit(HookEntry.run(
    tool: tool,
    input: input,
    environment: ProcessInfo.processInfo.environment,
    inbox: Inbox(directory: Inbox.defaultDirectory)
))
