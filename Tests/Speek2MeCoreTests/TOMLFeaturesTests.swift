import Testing
@testable import Speek2MeCore

struct TOMLFeaturesTests {
    @Test func appendsFeaturesTableWhenAbsent() {
        #expect(TOMLFeatures.enableHooks(in: "model = \"gpt-5.2\"\n") == "model = \"gpt-5.2\"\n\n[features]\nhooks = true\n")
        #expect(TOMLFeatures.enableHooks(in: "") == "[features]\nhooks = true\n")
    }

    @Test func addsKeyToExistingTable() {
        #expect(TOMLFeatures.enableHooks(in: "[features]\nfoo = 1\n\n[tui]\nx = 1\n") == "[features]\nhooks = true\nfoo = 1\n\n[tui]\nx = 1\n")
    }

    @Test func replacesFalseAndIsIdempotent() {
        let once = TOMLFeatures.enableHooks(in: "[features]\nhooks = false\n")
        #expect(once == "[features]\nhooks = true\n")
        #expect(TOMLFeatures.enableHooks(in: once) == once)
        #expect(TOMLFeatures.hooksEnabled(in: once))
        #expect(!TOMLFeatures.hooksEnabled(in: "[features]\nhooks = false\n"))
        #expect(!TOMLFeatures.hooksEnabled(in: "[tui]\nhooks = true\n"))
    }
}

extension TOMLFeaturesTests {
    @Test func handlesDottedRootKeys() {
        #expect(TOMLFeatures.hooksEnabled(in: "features.hooks = true\n"))
        #expect(TOMLFeatures.enableHooks(in: "features.hooks = false\n[tui]\nx = 1\n") == "features.hooks = true\n[tui]\nx = 1\n")
        // Another dotted features key means a [features] header would redefine the table; add a dotted key instead.
        #expect(TOMLFeatures.enableHooks(in: "model = \"gpt-5.2\"\nfeatures.other = true\n\n[tui]\nx = 1\n")
                == "model = \"gpt-5.2\"\nfeatures.other = true\nfeatures.hooks = true\n\n[tui]\nx = 1\n")
        // A dotted key inside another table is not a root key.
        #expect(!TOMLFeatures.hooksEnabled(in: "[tui]\nfeatures.hooks = true\n"))
    }
}
