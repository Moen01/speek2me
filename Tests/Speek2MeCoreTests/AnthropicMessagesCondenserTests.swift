import Foundation
import Testing
@testable import Speek2MeCore

struct AnthropicMessagesCondenserTests {
    private func body(of request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func requestCarriesKeyModelAndWrappedMessage() throws {
        let request = try AnthropicMessagesCondenser.makeRequest(text: "all done", project: "rea", model: .haiku, instructions: "SYSTEM", apiKey: "sk-test")
        #expect(request.url == AnthropicMessagesCondenser.endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let json = try body(of: request)
        #expect(json["model"] as? String == "claude-haiku-5-5")
        #expect(json["system"] as? String == "SYSTEM")
        let messages = try #require(json["messages"] as? [[String: Any]])
        let content = try #require(messages.first?["content"] as? String)
        #expect(content.contains("<final_message project=\"rea\">"))
        #expect(content.contains("all done"))
    }

    @Test func parseResponseMapsErrorsAndText() throws {
        let unauthorized = Data(#"{"error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8)
        #expect(throws: CondenserError.invalidAPIKey("invalid x-api-key")) {
            try AnthropicMessagesCondenser.parseResponse(data: unauthorized, status: 401)
        }
        let limited = Data(#"{"error":{"type":"rate_limit_error","message":"slow down"}}"#.utf8)
        #expect(throws: CondenserError.rateLimited("slow down")) {
            try AnthropicMessagesCondenser.parseResponse(data: limited, status: 429)
        }
        let ok = Data(#"{"content":[{"type":"thinking","thinking":"hm"},{"type":"text","text":" Done. "},{"type":"text","text":"Two files."}],"stop_reason":"end_turn"}"#.utf8)
        #expect(try AnthropicMessagesCondenser.parseResponse(data: ok, status: 200) == "Done. Two files.")
        let refused = Data(#"{"content":[],"stop_reason":"refusal"}"#.utf8)
        #expect(throws: CondenserError.refused) {
            try AnthropicMessagesCondenser.parseResponse(data: refused, status: 200)
        }
    }

    @Test func missingKeyFailsBeforeAnyRequest() async {
        let condenser = AnthropicMessagesCondenser(apiKey: { nil })
        await #expect(throws: CondenserError.missingAPIKey) {
            try await condenser.condense("x", project: "p", model: .haiku, instructions: "s")
        }
    }
}
