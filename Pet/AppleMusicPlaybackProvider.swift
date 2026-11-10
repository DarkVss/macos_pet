import AppKit

/// Serializes Apple Events away from the UI and never launches Music.
actor AppleMusicPlaybackProvider: MusicPlaybackControlling {
    private var script: NSAppleScript?
    private var lastError: Int?

    func perform(_ command: MusicPlaybackCommand) async -> Bool {
        let instruction: String
        switch command {
        case .previous: instruction = "previous track"
        case .togglePlayPause: instruction = "playpause"
        case .next: instruction = "next track"
        }
        guard let commandScript = NSAppleScript(source: """
            if application id "com.apple.Music" is not running then return false
            with timeout of 2 seconds
                tell application id "com.apple.Music" to \(instruction)
            end timeout
            return true
            """) else { return false }
        var error: NSDictionary?
        let result = commandScript.executeAndReturnError(&error)
        if let error {
            NSLog("Apple Music command failed (Apple Event error %ld)",
                  error[NSAppleScript.errorNumber] as? Int ?? 0)
            return false
        }
        return result.booleanValue
    }

    func playbackState() async -> MusicPlaybackState {
        if script == nil {
            script = NSAppleScript(source: """
                if application id "com.apple.Music" is not running then return "stopped"
                with timeout of 2 seconds
                    tell application id "com.apple.Music"
                        set currentState to player state
                        if currentState is playing then return "playing"
                        if currentState is paused then return "paused"
                        return "stopped"
                    end tell
                end timeout
                """)
        }
        guard let script else { return .unavailable }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int
            if code != lastError {
                NSLog("Apple Music playback status unavailable (Apple Event error %ld)", code ?? 0)
                lastError = code
            }
            return .unavailable
        }
        lastError = nil
        return MusicPlaybackState(rawValue: result.stringValue ?? "") ?? .unavailable
    }
}
