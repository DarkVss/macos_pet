import AppKit

/// Serializes Apple Events away from the UI; never launches Music or changes playback.
actor AppleMusicPlaybackProvider: MusicPlaybackProviding {
    private var script: NSAppleScript?
    private var lastError: Int?

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
