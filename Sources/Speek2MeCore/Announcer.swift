import Foundation

/// The words for one event: project name first, so you know who is talking.
public enum Announcer {
    public static func text(for event: SessionEvent, condensed: String) -> String {
        let project = event.project
        switch (event.kind, event.reason) {
        case (.turnComplete, _):
            return "\(project): \(condensed)"
        case (.needsYou, .permission):
            let detail = RawCondenser.condense(event.text, maxSentences: 1)
            return detail.isEmpty ? "\(project) needs your approval." : "\(project) needs you: \(detail)"
        case (.needsYou, .question):
            let detail = RawCondenser.condense(event.text, maxSentences: 1)
            return detail.isEmpty ? "\(project) has a question for you." : "\(project) has a question: \(detail)"
        case (.needsYou, .idle), (.needsYou, .none):
            return "\(project) is waiting for you."
        }
    }
}
