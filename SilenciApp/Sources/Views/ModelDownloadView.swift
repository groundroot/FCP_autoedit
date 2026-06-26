import SwiftUI

/// Sheet that shows all available MLX models with download status and controls.
struct ModelDownloadView: View {
    var modelManager: ModelManager
    var pythonEnv: PythonEnvironment
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "cpu")
                    .foregroundStyle(.cyan)
                    .font(.title2)
                Text(L10n.tr("model.title"))
                    .font(.title3.bold())
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)

            Text(L10n.tr("model.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(modelManager.models.indices, id: \.self) { idx in
                        ModelRowView(
                            model: modelManager.models[idx],
                            pythonEnv: pythonEnv,
                            modelManager: modelManager
                        )
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Text(L10n.tr("model.cache_hint"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(L10n.tr("model.refresh")) {
                    modelManager.refreshAvailability()
                }
                .font(.subheadline)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 460, height: 420)
        .background(.ultraThinMaterial)
        .onAppear { modelManager.refreshAvailability() }
    }
}

struct ModelRowView: View {
    var model: ModelManager.MLXModel
    var pythonEnv: PythonEnvironment
    var modelManager: ModelManager

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: model.isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.title2)
                    .foregroundStyle(model.isDownloaded ? .green : .secondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.subheadline.bold())
                    Text(model.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(modelManager.formattedSize(model.approxSizeMB))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if let progress = model.downloadProgress {
                    VStack(alignment: .trailing, spacing: 4) {
                        ProgressView(value: progress)
                            .frame(width: 80)
                        Text(L10n.tr("model.downloading", Int(progress * 100)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if model.isDownloaded {
                    Text(L10n.tr("model.downloaded"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    Button(L10n.tr("model.download")) {
                        Task {
                            await modelManager.downloadModel(id: model.id, environment: pythonEnv)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .controlSize(.small)
                    .disabled(!pythonEnv.state.isReady)
                }
            }
            .padding(14)

            if let err = model.downloadError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(err).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.tr("model.retry")) {
                        Task {
                            await modelManager.downloadModel(id: model.id, environment: pythonEnv)
                        }
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.red.opacity(0.08))
            }
        }
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
