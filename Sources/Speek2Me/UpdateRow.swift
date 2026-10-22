import SwiftUI
import Speek2MeCore

/// The installed version, a button that asks GitHub for a newer release, and a blue button
/// that installs it.
struct UpdateRow: View {
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    @State private var checking = false
    @State private var outcome: Result<UpdateChecker.Result, Error>?
    @State private var step: SelfUpdater.Step?
    @State private var installError: String?

    var body: some View {
        LabeledContent("Version \(version)") {
            HStack {
                if case .success(.available(let update)) = outcome {
                    Button(installTitle(update)) { Task { await install(update) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(step != nil)
                }
                Button(checking ? "Checking…" : "Check for Updates") {
                    Task { await check() }
                }
                .disabled(checking || step != nil)
            }
        }
        // Checks each time the tab opens, so a waiting update shows without a click.
        .task { await check() }
        switch outcome {
        case .success(.available(let update)):
            if let installError {
                HStack {
                    Text("Could not install: \(installError)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Link("Open release page", destination: update.page).font(.caption)
                }
            }
        case .success(.upToDate):
            Text("You have the latest version.").foregroundStyle(.secondary)
        case .failure(let error):
            Text("Could not check for updates: \(error.localizedDescription)")
                .font(.caption)
                .foregroundStyle(.secondary)
        case nil:
            EmptyView()
        }
    }

    private func installTitle(_ update: UpdateChecker.Update) -> String {
        switch step {
        case .downloading: "Downloading…"
        case .installing: "Installing…"
        case nil: "Update to \(update.version)"
        }
    }

    private func check() async {
        checking = true
        defer { checking = false }
        do {
            outcome = .success(try await UpdateChecker.check(currentVersion: version))
        } catch {
            outcome = .failure(error)
        }
    }

    /// On success Speek2Me quits and the new version opens, so only failures come back here.
    private func install(_ update: UpdateChecker.Update) async {
        installError = nil
        defer { step = nil }
        do {
            try await SelfUpdater.install(update) { step = $0 }
        } catch {
            installError = error.localizedDescription
        }
    }
}
