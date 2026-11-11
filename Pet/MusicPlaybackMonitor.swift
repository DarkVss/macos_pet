import Foundation

enum MusicPlaybackState: String, Sendable {
    case unavailable
    case stopped
    case paused
    case playing
}

struct MusicPlaybackSnapshot: Equatable, Sendable {
    var state: MusicPlaybackState
    var artist = ""
    var title = ""
}

/// Each player integration supplies the same renderer-independent state.
protocol MusicPlaybackProviding: Sendable {
    func playbackSnapshot() async -> MusicPlaybackSnapshot
}

enum MusicPlaybackCommand: Int, CaseIterable, Sendable {
    case previous
    case togglePlayPause
    case next
}

protocol MusicPlaybackControlling: MusicPlaybackProviding {
    func perform(_ command: MusicPlaybackCommand) async -> Bool
}

@MainActor
final class MusicPlaybackMonitor {
    private let provider: any MusicPlaybackProviding
    private var task: Task<Void, Never>?

    init(provider: any MusicPlaybackProviding) {
        self.provider = provider
    }

    func start(onChange: @escaping @MainActor (MusicPlaybackSnapshot) -> Void) {
        guard task == nil else { return }
        let provider = provider
        task = Task {
            var previous: MusicPlaybackSnapshot?
            while !Task.isCancelled {
                let state = await provider.playbackSnapshot()
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
