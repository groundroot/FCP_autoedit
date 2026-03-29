import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            // Left panel — transcript list (S04)
            VStack {
                Text("Transcript")
                    .font(.headline)
                    .padding(.top)
                Spacer()
                Text("영상을 불러오세요")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(minWidth: 250)
        } detail: {
            // Right panel — video preview + timeline
            VStack(spacing: 0) {
                // Video player placeholder (S02)
                ZStack {
                    Rectangle()
                        .fill(.black)
                    Text("Video Preview")
                        .foregroundStyle(.white.opacity(0.5))
                        .font(.title2)
                }
                .frame(maxHeight: .infinity)

                Divider()

                // Timeline bar placeholder (S05)
                ZStack {
                    Rectangle()
                        .fill(Color(.windowBackgroundColor))
                    Text("Timeline")
                        .foregroundStyle(.secondary)
                }
                .frame(height: 60)

                Divider()

                // Toolbar
                HStack {
                    Button("파일 열기") {
                        // File open (S02)
                    }
                    Spacer()
                    Button("분석 시작") {
                        // Analyze (S03)
                    }
                    .disabled(true)
                    Spacer()
                    Menu("내보내기") {
                        ForEach(ExportFormat.allCases) { format in
                            Button(format.displayName) {
                                // Export (S06)
                            }
                        }
                    }
                    .disabled(true)
                }
                .padding(8)
            }
        }
    }
}

#Preview {
    ContentView()
}
