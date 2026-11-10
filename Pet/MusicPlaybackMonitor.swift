import Foundation

enum MusicPlaybackState: String, Sendable {
    case unavailable
    case stopped
    case paused
    case playing
}

/// Each player integration supplies the same renderer-independent state.
protocol MusicPlaybackProviding: Sendable {
    func playbackState() async -> MusicPlaybackState
}

@MainActor
final class MusicPlaybackMonitor {
    private let provider: any MusicPlaybackProviding
    private var task: Task<Void, Never>?

    init(provider: any MusicPlaybackProviding) {
        self.provider = provider
    }

    func start(onChange: @escaping @MainActor (MusicPlaybackState) -> Void) {
        guard task == nil else { return }
        let provider = provider
        task = Task {
            var previous: MusicPlaybackState?
            while !Task.isCancelled {
                let state = await provider.playbackState()
                guard !Task.isCancelled else { return }
                if state != previous {
                    previous = state
                    onChange(state)
                }
                do { try await Task.sleep(for: .milliseconds(500)) }
                catch { return }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }
}
