import Testing
@testable import Speek2MeCore

struct RawCondenserTests {
    @Test func stripsMarkdownPathsAndCapsSentences() {
        let input = "## Done\n\nChanged `src/app.ts` and /Users/moen/x.ts. See https://example.com. Tests pass! Next step is yours. Fourth sentence."
        #expect(RawCondenser.condense(input, maxSentences: 3) == "Done. Changed src/app.ts and a file. See a link.")
    }

    @Test func dropsCodeFences() {
        #expect(RawCondenser.condense("Run:\n```sh\nls\n```\nThen go.", maxSentences: 3) == "Run: Then go.")
    }

    @Test func stripsListMarkersAndEmphasis() {
        let input = "- **Bold** item one.\n- _second_ item.\n1. third `code` item?"
        #expect(RawCondenser.condense(input, maxSentences: 5) == "Bold item one. second item. third code item?")
    }

    @Test func capsAtOneSentenceAndHandlesEmpty() {
        #expect(RawCondenser.condense("A. B. C.", maxSentences: 1) == "A.")
        #expect(RawCondenser.condense("   \n", maxSentences: 3) == "")
    }
}
