# Pet

A macOS desktop companion. The initial prototype uses sprites, with behavior
kept independent of rendering so a 3D implementation can be added later.

## Development

Open `Pet.xcodeproj` in Xcode, select the Pet scheme, and run it.
Requires macOS 14 or later.

The default pet is **Киноко v0.1**, imported from the user's custom pet
`pet_6add012b33e08191870a9dde6ad7e9a5`. Drag her to move the transparent
floating window. The animation picker below the pet is currently enabled by
default for development. Toggle **Отладочное меню эмоций** from the paw icon
to hide or show it. Selecting an entry starts that animation.
Showing the picker preserves the pet's screen position.
Dragging horizontally temporarily selects the matching running animation;
releasing the mouse restores the previous activity and gaze direction.
The available states, in order, are Ожидание (the default), Отдых,
Бег вправо, Бег влево, Приветствие, and Слушаю музыку.
Ожидание uses a fixed body and silhouette with blinking only. Body, hair, and
tail pixels stay identical throughout the cycle; eye poses are aligned before
compositing onto the fixed reference frame.
The menu bar also provides 16 gaze directions (0° is up, clockwise) and quit.
Right-click the pet to open the same shared menu as the paw icon.
Use **Направление взгляда → Сбросить угол взгляда** to resume the selected
activity animation without a forced gaze direction.

The avatar package in `Pet/Resources/Kinoko.bundle` contains 149 transparent
192×208 frames: four 30-frame animation loops, a 12-frame music-listening loop,
16 gaze directions, and one rest pose. Each state has a separate `sprites.png`; `manifest.json` defines its
frame count, grid, FPS, and pause. See [the package format](docs/avatar-format.md).
The four original animation loops were expanded from Kinako's original artwork using
bidirectional optical flow with occlusion-aware blending. The app reads ordinary
PNG sheets, so future user avatars will not need Xcode atlas compilation.
No network access or Pets service is required at runtime.

Rendering follows the selected animation's FPS (30 for the original loops,
6 for music listening).
Static rest and gaze poses request only 1 FPS. Validated images are reused;
SpriteKit textures are created on first use and cached per sheet, so startup
only prepares the waiting animation rather than every state.
The original animated cycles are one second long, followed by their configured pause.
The music-listening animation uses 12 generated keyframes at 6 FPS for a two-second loop.
Intermediate poses are computed offline; the app only plays bundled textures,
with no runtime optical-flow processing or extra frame dissolves.
Fast motion and occlusions may still show interpolation artifacts; these
frames are not equivalent to an animator drawing every intermediate pose.
Waiting and greeting cycles include pauses to avoid excessively fast repetition.
Rest uses an existing closed-eye idle frame; the source has no sleep animation.
Слушаю музыку is selected manually. While Apple Music is playing, a «Музыка»
placeholder appears below the pet and above the animation picker. It remains
visible while paused, and disappears when Music stops or is closed. Browser calls and other apps do not
activate it. Pet reads Music's `player state` through Apple Events with a 500 ms
interval between responses on a separate actor, without launching Music or changing playback.
The first query to a running Music app may ask for Automation permission.
App Sandbox stays enabled; the scripting entitlement targets only Music's
`com.apple.Music.playback` access group. Accessibility is not required.

`MusicPlaybackProviding` separates player integration from the monitor and UI.
`AppleMusicPlaybackProvider` is the initial implementation; other players can
supply the same playback-state contract later. Playback controls and track
metadata are not implemented yet.

## Structure

- `PetState.swift`: shared state, rendering contract, and behavior controller.
- `SpriteAvatar.swift`: package manifest, resource loading, and validation.
- `SpritePetScene.swift`: sprite presentation and window dragging input.
- `PetApp.swift`: application lifecycle, floating panel, and menu bar controls.

- `MusicPlaybackMonitor.swift`: shared player-state contract and polling lifecycle.
- `AppleMusicPlaybackProvider.swift`: Apple Music state via its scripting interface.
