import SwiftUI

/// App-owned metadata only. Model prose never creates an executable UI action.
struct ChatPluginSuggestionView: View {
    @Bindable var model: AppModel
#if DEBUG
    @Environment(\.pluginPresentationFixtureActions) private var fixtureActions
#endif
    @State private var presentation: Presentation?
    @State private var failure: String?
    private struct Presentation: Identifiable {
        let route: ChatPluginReviewRoute
        let arguments: String
        var id: UUID { route.id }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let pending = model.pendingPluginProposal {
                Text("Suggested call · not executed").font(.subheadline.bold())
                    .accessibilityIdentifier("chat.pluginSuggestion.status")
                Text(pending.proposal.name).font(.body.monospaced()).textSelection(.enabled)
                Text("Proposed on this iPhone using the connected tool catalog. Nothing has been sent to the tool. Review the exact arguments and destination before choosing Run.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Review suggested call") { openReview(id: pending.id) }
                        .disabled(model.isGenerating || model.isPreparingAutomaticModel)
                        .accessibilityIdentifier("chat.pluginSuggestion.review")
                    Button("Dismiss") {
                        model.dismissPluginProposal(id: pending.id)
                        presentation = nil; failure = nil
                    }.accessibilityIdentifier("chat.pluginSuggestion.dismiss")
                }
            }
            if let failure { Text(failure).font(.caption).foregroundStyle(.orange) }
        }
        .padding(.horizontal)
        .sheet(item: $presentation) { item in
            NavigationStack {
                if let broker = model.plugins,
                   item.route.request.matches(conversation: model.pluginResultConversationContext,
                       provider: model.pluginProposalProviderContext, connection: broker.activeConnection?.id,
                       catalog: broker.proposalCatalogID) {
                    PluginToolCallView(broker: broker, tool: item.route.tool,
                        initialArguments: item.arguments, model: model, request: item.route.request)
                        .toolbar { ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { presentation = nil }
                                .accessibilityIdentifier("chat.pluginSuggestion.close")
                        } }
#if DEBUG
                        .toolbar {
                            if let fixtureActions, RootViewRegressionFixtureHost.requestedMode == "plugin-suggestion" {
                                ToolbarItemGroup(placement: .bottomBar) {
                                    ForEach(["conversation", "provider", "catalog"], id: \.self) { kind in
                                        Button(kind) { fixtureActions.change(kind) }
                                            .accessibilityIdentifier("fixture.plugin.change." + kind)
                                    }
                                }
                            }
                        }
#endif
                } else {
                    Text("This suggestion is no longer current. Close it and ask again. No new call was sent.")
                }
            }
        }
        .onChange(of: model.isGenerating) { _, active in if active { invalidate() } }
        .onChange(of: model.isPreparingAutomaticModel) { _, active in if active { invalidate() } }
        .onChange(of: model.pluginResultConversationContext) { _, _ in invalidate() }
        .onChange(of: model.pluginProposalProviderContext) { _, _ in invalidate() }
        .onChange(of: model.plugins?.proposalCatalogID) { _, _ in invalidate() }
        .onChange(of: model.plugins?.activeConnection?.id) { _, _ in invalidate() }
    }
    private func openReview(id: UUID) {
        // This API revalidates the current pending receipt, origin, provider and
        // live catalog. It does not approve, dispatch, or clear the suggestion.
        guard let route = model.pluginProposalReviewRoute(id: id) else {
            failure = "This suggestion changed or expired. Ask again; no call was sent."
            return
        }
        do {
            let bytes = try route.arguments.encoded(maximumBytes: 16_384)
            // Consume only the matching app-owned suggestion, not an approval.
            // The frozen route remains valid for explicit Review/Run in the sheet.
            model.dismissPluginProposal(id: route.id)
            presentation = Presentation(route: route, arguments: String(decoding: bytes, as: UTF8.self))
            failure = nil
        } catch {
            failure = "The proposed arguments could not be opened safely. No call was sent."
        }
    }
    private func invalidate() { presentation = nil; failure = nil }
}
