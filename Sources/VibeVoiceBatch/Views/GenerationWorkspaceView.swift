import SwiftUI
import VibeVoiceBatchCore

struct GenerationWorkspaceView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selection: WorkstationSelection?

    var body: some View {
        HSplitView {
            GenerationListView(selection: $selection)
                .frame(minWidth: 230, idealWidth: 280, maxWidth: 380)

            generationDetail
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var generationDetail: some View {
        switch selection ?? .section(.history) {
        case .section(.history):
            EditorView()
        case .historySession(let sessionID):
            if let session = store.session(id: sessionID) {
                SessionDetailView(record: session)
            } else {
                MissingHistorySelectionView(sessionID: sessionID)
            }
        case .section(_):
            EditorView()
        }
    }
}
