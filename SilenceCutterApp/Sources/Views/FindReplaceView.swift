import SwiftUI

/// Inline find-and-replace bar for transcript text.
struct FindReplaceView: View {
    @Bindable var analysisService: AnalysisService
    @Binding var isVisible: Bool
    @State private var searchText = ""
    @State private var replaceText = ""
    @State private var replacedCount = 0
    @State private var showResult = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("찾기", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 150)

            TextField("치환", text: $replaceText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 150)

            Button("전체 치환") {
                let before = analysisService.segments.map(\.text).joined()
                analysisService.replaceAll(search: searchText, with: replaceText)
                // Count approximate replacements
                let diff = before.components(separatedBy: searchText).count - 1
                replacedCount = max(0, diff)
                showResult = true
            }
            .disabled(searchText.isEmpty)

            if showResult {
                Text("\(replacedCount)건 치환")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                isVisible = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
