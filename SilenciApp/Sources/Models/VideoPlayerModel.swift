import AVFoundation

/// Observable model that owns an AVPlayer and tracks playback state.
/// Used by VideoPlayerView for display and by downstream slices (S04) for seek integration.
@MainActor
@Observable
final class VideoPlayerModel {

    // MARK: - Published state

    /// The AVPlayer instance. Nil when no video is loaded.
    private(set) var player: AVPlayer?

    /// URL of the currently loaded video file.
    private(set) var videoURL: URL?

    /// Current playback position in seconds.
    var currentTime: TimeInterval = 0

    /// Total duration of the loaded video in seconds.
    private(set) var duration: TimeInterval = 0

    /// Whether the player is currently playing.
    private(set) var isPlaying: Bool = false

    /// Segments mirror — kept in sync by ContentView.
    /// Used to skip discarded segments during playback.
    var segments: [Segment] = []

    /// When true, playback skips over discarded (isKept == false) segments automatically.
    var skipDiscardedSegments = false

    // MARK: - Private

    /// Token returned by addPeriodicTimeObserver — must be removed before deallocation.
    /// `nonisolated(unsafe)` allows deinit access; `@ObservationIgnored` prevents
    /// the @Observable macro from wrapping it in @ObservationTracked.
    @ObservationIgnored
    private nonisolated(unsafe) var timeObserver: Any?

    /// Stashed reference for deinit cleanup (deinit can't access @MainActor player).
    @ObservationIgnored
    private nonisolated(unsafe) var playerForCleanup: AVPlayer?

    // MARK: - Public API

    /// Load a video file from the given URL. Tears down any existing observer
    /// before setting up the new item to prevent observer leaks.
    func loadVideo(url: URL) {
        // Clean up existing observer first.
        removeObserver()

        let item = AVPlayerItem(url: url)

        if player == nil {
            player = AVPlayer(playerItem: item)
        } else {
            player?.replaceCurrentItem(with: item)
        }
        playerForCleanup = player

        videoURL = url
        currentTime = 0
        duration = 0
        isPlaying = false

        // Read duration asynchronously from the asset.
        Task { [weak self] in
            guard let self else { return }
            do {
                let loadedDuration = try await item.asset.load(.duration)
                self.duration = CMTimeGetSeconds(loadedDuration)
            } catch {
                print("[VideoPlayerModel] Failed to load duration: \(error)")
                self.duration = 0
            }
        }

        // Set up periodic time observer for currentTime / isPlaying tracking.
        installObserver()
    }

    /// Whether a seek operation is currently in progress.
    private var isSeeking = false

    /// Seek to a specific time in seconds.
    /// Uses tolerant seek for responsiveness — avoids blocking on precise frame decode.
    func seek(to time: TimeInterval) {
        guard let player, !isSeeking else { return }
        isSeeking = true
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: CMTime(seconds: 0.1, preferredTimescale: 600),
                     toleranceAfter: CMTime(seconds: 0.1, preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isSeeking = false
            }
        }
    }

    /// Toggle between play and pause.
    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying = !isPlaying
    }

    // MARK: - Observer management

    private func installObserver() {
        guard let player else { return }
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] cmTime in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = CMTimeGetSeconds(cmTime)
                self.isPlaying = self.player?.rate != 0
                if self.skipDiscardedSegments && self.isPlaying {
                    self.skipIfDiscarded()
                }
            }
        }
    }

    private func skipIfDiscarded() {
        guard !isSeeking else { return }
        let t = currentTime
        guard let discarded = segments.first(where: { !$0.isKept && t >= $0.start && t < $0.end }) else { return }
        if let next = segments.first(where: { $0.isKept && $0.start >= discarded.end }) {
            seek(to: next.start)
        } else {
            player?.pause()
            isPlaying = false
        }
    }

    private func removeObserver() {
        if let observer = timeObserver, let player {
            player.removeTimeObserver(observer)
        }
        timeObserver = nil
    }

    deinit {
        // removeTimeObserver must be called exactly once per addPeriodicTimeObserver.
        // Uses nonisolated(unsafe) stored refs since deinit is nonisolated in Swift 6.
        if let observer = timeObserver, let player = playerForCleanup {
            player.removeTimeObserver(observer)
        }
        timeObserver = nil
        playerForCleanup = nil
    }
}
