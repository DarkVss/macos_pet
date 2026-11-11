# Pet

A macOS desktop companion. SpriteKit and SceneKit renderers share the same behavior and desktop controls.

## Development

Open `Pet.xcodeproj` in Xcode, select the Pet scheme, and run it.
Requires macOS 14 or later.

The sprite pet is **Кинако v0.1**, imported from the user's custom pet
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

The avatar package in `Pet/Resources/Kinako.bundle` contains 149 transparent
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
While Apple Music is playing or paused, a music block appears below the pet
and above the animation picker. It contains the artist and track title above previous, play/pause, and next
buttons. Each metadata row is 192 points wide, matching the animation picker.
Short text is centered; overflowing text scrolls back and forth with pauses at
the ends. Unchanged metadata does not restart scrolling, and hidden rows stop
animating. Full text is also available in tooltips. It disappears when Music stops or is closed. Browser calls
and other apps do not activate it. The central button follows the actual player
state; controls are briefly disabled while a command is in flight.

The pet automatically uses Слушаю музыку while the block is visible. Dragging
temporarily overrides it with running; releasing resumes the music reaction.
When the block disappears, the manually selected activity and gaze are restored. Pet reads Music's `player state` through Apple Events with a 500 ms
interval between responses on a separate actor, without launching Music. Playback changes only in response to the music buttons.
The first query to a running Music app may ask for Automation permission.
App Sandbox stays enabled; the scripting entitlement targets only Music's
`com.apple.Music.playback` access group. Accessibility is not required.

`MusicPlaybackProviding` separates player integration from the monitor and UI.
`AppleMusicPlaybackProvider` is the initial implementation; other players can
supply the same playback snapshot (state, artist, and title) later. `MusicPlaybackControlling` adds
semantic previous, play/pause, and next commands independently of the player.
Metadata changes are observed even when playback stays in the same state.
Missing metadata is displayed as «Неизвестный исполнитель» or «Без названия».

The player and development picker share a rounded translucent dark backdrop
with a consistent dark appearance for readable text and controls on any desktop.
A soft silhouette shadow follows the current sprite frame; source artwork and
alpha channels are unchanged. Shadow rasterization is cached only for static poses.

## 3D avatar

**Кинако 3D v0.1** is bundled in `Pet/Resources/Kinako3D.bundle/avatar.glb`.
Select **Аватар** in the paw menu or the same right-click menu to switch between
3D and sprites. The selection survives relaunches; the first launch selects 3D.
If 3D loading fails, startup falls back to sprites and reports the error.
A failed selection preserves the existing avatar.

The Meshy/Mixamo export contains 14,870 triangles and 117 bones, including 50 dedicated tail segments.
The tail is rebuilt as a separate closed mesh, rooted at the pelvis. Its rest
shape hangs down behind the legs instead of retaining the sideways curl from
the source image. The old mixed hair/leg attachment is removed and capped;
source fur colors are reused in a dedicated tail texture. The original
Running/Walking clips are retained and supplemented with tail motion and a
TailIdle clip. Every tail vertex is controlled only by the tail chain, avoiding a stretched
connector between the pelvis and the old hair-driven attachment. The 3D renderer currently exposes waiting with a gentle tail sway (the body keeps its exported rest pose)
and running left/right. It turns the model and loops Running in place at 30 FPS;
the running pose turns 30° toward the viewer from either side profile. It does not move the window automatically. Dragging uses the same constraints
as sprites. Unsupported rest, greeting, and music reactions are disabled in the
picker; the sprite gaze menu is hidden in 3D. Music controls remain available
without overriding the 3D activity. Waiting also renders at 30 FPS while the tail animation is active.

`GLBAvatar` reads the subset of glTF 2.0 used by this bundled asset: embedded
textures, triangle meshes, skinning, and linear TRS animation. It is not a
user-facing general GLB importer. SceneKit uses the base-color texture without
extra lighting for a readable stylized appearance; the other source maps remain
in the original asset. Hair and facial expressions remain unchanged. Tail motion uses authored
skeletal keyframes, without physics simulation. Animation quality and resource use depend on the chosen asset;
no general performance guarantee is implied.

## Structure

- `PetState.swift`: shared state, rendering contract, and behavior controller.
- `SpriteAvatar.swift`: package manifest, resource loading, and validation.
- `SpritePetScene.swift`: sprite presentation.
- `DraggablePetView.swift`: shared dragging and context-menu input.
- `GLBAvatar.swift`: bundled GLB geometry, texture, skeleton, and clip loading.
- `ModelPetRenderer.swift`: 3D presentation and semantic activity mapping.
- `PetApp.swift`: application lifecycle, floating panel, and menu bar controls.

- `MusicPlaybackMonitor.swift`: shared player-state contract and polling lifecycle.
- `AppleMusicPlaybackProvider.swift`: Apple Music state and commands via its scripting interface.
- `MusicControlsView.swift`: player-independent metadata and button presentation.
- `MarqueeTextView.swift`: clipped, centered text with overflow-only scrolling.

- `ControlsBackdropView.swift`: shared contrast surface for controls.
