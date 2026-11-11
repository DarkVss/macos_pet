import AppKit

/// Serializes Apple Events away from the UI and never launches Music.
actor AppleMusicPlaybackProvider: MusicPlaybackControlling {
    private var script: NSAppleScript?
    private var lastError: Int?
    private var lastMetadataError: Int?
    private var lastMetadata: (artist: String, title: String)?

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

    func playbackSnapshot() async -> MusicPlaybackSnapshot {
        if script == nil {
            script = NSAppleScript(source: """
                if application id "com.apple.Music" is not running then return {"stopped", "", "", 0}
                with timeout of 2 seconds
                    tell application id "com.apple.Music"
                        set currentState to player state
                        set statusText to "stopped"
                        if currentState is playing then set statusText to "playing"
                        if currentState is paused then set statusText to "paused"
                        if statusText is "stopped" then return {statusText, "", "", 0}
                        set artistName to ""
                        set trackTitle to ""
                        set metadataError to 0
                        try
                            set {artistName, trackTitle} to {artist, name} of current track
                            set artistName to artistName as text
                            set trackTitle to trackTitle as text
                        on error number errorNumber
                            set metadataError to errorNumber
                            set artistName to ""
                            set trackTitle to ""
                        end try
                        return {statusText, artistName, trackTitle, metadataError}
                    end tell
                end timeout
                """)
        }
        guard let script else { return MusicPlaybackSnapshot(state: .unavailable) }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int
            if code != lastError {
                NSLog("Apple Music playback status unavailable (Apple Event error %ld)", code ?? 0)
                lastError = code
            }
            return MusicPlaybackSnapshot(state: .unavailable)
        }
        lastError = nil
        guard result.numberOfItems == 4,
              let value = result.atIndex(1)?.stringValue,
              let state = MusicPlaybackState(rawValue: value) else {
            return MusicPlaybackSnapshot(state: .unavailable)
        }
        let metadataError = Int(result.atIndex(4)?.int32Value ?? 0)
        if metadataError != 0 && metadataError != lastMetadataError {
            NSLog("Apple Music metadata unavailable (Apple Event error %ld)", metadataError)
        }
        lastMetadataError = metadataError == 0 ? nil : metadataError
        if state == .stopped {
            lastMetadata = nil
        } else if metadataError == 0 {
            lastMetadata = (result.atIndex(2)?.stringValue ?? "", result.atIndex(3)?.stringValue ?? "")
        }
        return MusicPlaybackSnapshot(state: state,
                                     artist: lastMetadata?.artist ?? "",
                                     title: lastMetadata?.title ?? "")
    }
}
