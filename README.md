# CROWD RUSH — First Playable Vertical Slice

Mobile-first 3D crowd runner prototype built with **Godot 4.6 + GDScript**, Mobile renderer, Jolt physics.
Fully offline: no server, no login, no backend, no network calls.

> NUMBER → CHOICE → CROWD GROWTH → CHAOS → PAYOFF

The project launches straight into a ~10 s in-engine cinematic intro, hands control to the player,
runs 4 gates + 1 obstacle, and ends with the GIANT GUARD boss fight and a result screen
(~65 s total). **PLAY AGAIN** restarts instantly (the intro is skipped on replays).

---

## 1. Project files

```
project.godot            Mobile renderer, Jolt, landscape, touch-from-mouse, 1280x720 base
export_presets.cfg       Android preset (arm64-v8a + armeabi-v7a)
icon.svg
scenes/
  main/Main.tscn            root scene (GameManager)
  main/IntroSequence.tscn   10 s cinematic
  crowd/Crowd.tscn          CrowdManager + ActivePhysicsActors pool
  crowd/Runner.tscn         single runner (used by physics actors)
  crowd/PhysicsActor.tscn   RigidBody3D + capsule + Runner
  gates/Gate.tscn           two-panel gate
  gates/ObstacleBarrier.tscn
  boss/Boss.tscn            GIANT GUARD
  boss/BossArena.tscn
  environment/Environment.tscn
  player/CameraRig.tscn
  ui/HUD.tscn
scripts/
  main/      game_manager.gd, level_manager.gd, intro_sequence.gd
  crowd/     crowd_manager.gd, formation.gd, runner_rig.gd, runner_visual.gd,
             physics_actor.gd, physics_actor_pool.gd
  gates/     gate.gd, gate_manager.gd, obstacle_barrier.gd
  boss/      boss_controller.gd, boss_arena.gd
  player/    input_controller.gd, camera_controller.gd
  systems/   audio_manager.gd, vfx_manager.gd, mesh_factory.gd, palette.gd,
             save_data.gd, debug_overlay.gd
  environment/environment_builder.gd
  ui/        hud.gd
materials/   crowd_runner.gdshader, vc_world.gdshader, gate_curtain.gdshader
assets/
  sounds/    26 synthesized WAVs (22 kHz mono)
  fonts/     LilitaOne-Regular.ttf + OFL.txt
tools/
  generate_sounds.py     regenerates every sound/music file (numpy)
  autoplay_test.gd       headless full playthrough bot (smoke test)
  screenshot_test.gd     renders screenshots at given times
  perf_test.gd           CPU benchmark of the crowd update
```

`assets/characters`, `assets/environment`, `assets/textures`, `assets/vfx` and `animations/` are empty on
purpose: all geometry, materials and animation are procedural (see §11). They are there for when real
assets replace the procedural ones.

## 2. Scene hierarchy

```
Main (Node3D, GameManager)
├─ Environment         sky/fog/sun, road, sidewalks, MultiMesh buildings/props/clouds, colliders
├─ Level (LevelManager) builds the gates from GATE_LAYOUT, places obstacle/arena/boss
│  ├─ GateManager      gate detection + feedback chain
│  ├─ ObstacleBarrier  frozen RigidBody3D barricades, cones, crates
│  ├─ BossArena        plaza, rings, containers, floodlights, swaying banners, end wall
│  ├─ Boss             GIANT GUARD (pivot hierarchy, tweened poses)
│  └─ Gate1..Gate4     (instanced at runtime)
├─ Crowd (CrowdManager)
│  ├─ MM_body / MM_head / MM_hair_0 / MM_hair_1 / MM_arm / MM_thigh / MM_shin / MM_shadow
│  ├─ Sensor (Area3D)  sized to the formation every frame
│  └─ ActivePhysicsActors (PhysicsActorPool, 24 × PhysicsActor)
├─ PreviewCrowd        second CrowdManager used only by the intro's "×2 preview" shot
├─ CameraRig (CameraController) └─ Camera3D
├─ InputController
├─ AudioManager        14 SFX voices, 2 music players (crossfade), ambience + footstep loops
├─ VFXManager          pooled CPUParticles3D, shockwave rings, 3D pop text, ambient motes
├─ IntroSequence
├─ HUD (CanvasLayer)
└─ DebugOverlay (CanvasLayer, hidden; F6)
```

Game states (GameManager): `INTRO → PLAYING → BOSS_INTRO → BOSS_FIGHT → VICTORY` (or `FAILED`).
Signals: `crowd_size_changed`, `crowd_grew`, `crowd_hit`, `crowd_emptied`, `gate_passed`,
`boss_started`, `boss_damaged`, `boss_defeated`, `level_completed`, plus boss animation events
(`footstep`, `roared`, `slammed`, `swing_started`, `swing_hit`, `entrance_finished`).
No autoload singletons: GameManager injects references with `setup(...)` calls.

## 3. Main scripts

| Script | Role |
|---|---|
| `game_manager.gd` | State machine, wiring, obstacle trigger, boss fight damage, victory/failure, restart, debug keys |
| `level_manager.gd` | **All level tuning** (gate distances/ops, obstacle, arena, boss trigger) |
| `intro_sequence.gd` | Timeline of events + per-frame camera path over the live level |
| `crowd_manager.gd` | Count, spawning/despawning, movement, steering spring, slots, rendering, hits |
| `formation.gd` | Count → slot offsets (hex lattice, width-capped, cached), boss swarm arcs |
| `runner_rig.gd` | Procedural runner meshes + `pose_into()` for IDLE/RUN/HIT/KNOCKBACK/FALL/GET_UP/VICTORY/ATTACK (+ additive turn lean) |
| `physics_actor*.gd` | Temporary rigid-body runners and their pool |
| `gate.gd` / `gate_manager.gd` | Gate visuals + trigger; op math + feedback |
| `obstacle_barrier.gd` | Scripted barrier destruction |
| `boss_controller.gd` | GIANT GUARD build, idle, entrance, swing attack, damage flash, defeat |
| `camera_controller.gd` | Follow/boss/victory modes, zoom by crowd size, punch, trauma shake, blends |
| `input_controller.gd` | Touch/mouse drag + keyboard to steering target |
| `audio_manager.gd` / `vfx_manager.gd` | Pooled feedback systems |
| `hud.gd` | Counter, delta, progress, boss bar, cinematic text, letterbox, result panel |

## 4. How crowd spawning works

* The crowd is **data**, not nodes: each runner is a small `RunnerData` record (position, anim state,
  phase, look). Rendering uses **8 MultiMeshes** (one per body part + blob shadows), so 150 runners
  cost ~8 draw calls (+ shadow pass).
* `Formation.slots(n)` returns cached local offsets: a hexagonal lattice sorted by elliptical distance
  from the centre. The half-width is capped at 3.1 units (so the crowd fits through one gate panel);
  big crowds grow deeper instead of wider, and spacing compresses from 0.95 to 0.72.
* `add_runners(n)` raises the logical count immediately (HUD reacts at once), then queues spawns
  that pop in over ~0.36 s **next to random existing runners**, scale-bounce in with a hop, and flow
  into the outer slots. Slots are re-assigned by distance-to-centre so existing runners keep their places.
* Legs/arms are animated per runner with random phase offsets and cadences, so nobody runs in sync.
  RUN poses are pre-computed into a 32×9 (phase × lean) lookup table, which is why a big crowd is cheap.
* `remove_runners(n)` takes the **outer** slots first: up to 6 become physics actors pushed outward,
  the rest shrink away with a poof; front runners stumble; the formation closes the gaps.

## 5. How physics switching works

Normal runners never touch the physics engine. When a runner must react physically
(bad gate, barricade, boss swing), `CrowdManager._launch()` removes it from the crowd data and asks
`PhysicsActorPool.spawn()` for a pooled `PhysicsActor` (RigidBody3D + capsule + `Runner.tscn`).
The actor gets the runner's look/scale/transform, an impulse (outward/backward + upward) and a
random spin, plays KNOCKBACK (flailing) then FALL once it slows, and shrinks away after ~1.3–1.6 s
before returning to the pool. Max 24 actors exist; if all are busy the oldest is recycled.
Barricade pieces are frozen `RigidBody3D`s that are unfrozen only in the crowd's path and frozen
again after 4 s. The boss's hammer becomes a rigid body when it is defeated. Everything else is static.
Layers: 1 world, 2 props/debris, 4 actors, 16 crowd sensor, 32 gate triggers.

## 6. How gate calculations work

`Gate.apply_op(op, value, count)`: `ADD → count + v`, `MUL → count × v`, `SUB → max(0, count − v)`,
clamped to `CrowdManager.MAX_CROWD = 150`. The side is picked by the sign of the crowd centre X
(left panel x < 0, right panel x > 0). Detection: each gate's trigger `Area3D` fires when the crowd's
`Sensor` touches it (front of the crowd); a centre-crossing check is a fallback. While crossing, runners are
"funnelled" onto the chosen side so the crowd squeezes through the panel it picked.

Feedback chain per gate: burst particles at the panel, crowd ring + sparkle/multiply burst, big 3D pop
text ("×2!"), HUD counter roll + bounce + colour, HUD delta line `×2!  10 ▶ 20`, sound, camera
punch (+ FOV kick for ×, shake for −), panel flash/dim.

Level layout (`level_manager.gd`, 10 u ≈ 1 s):

| Distance | Event | Left | Right |
|---|---|---|---|
| 100 | Gate 1 | +10 | ×2 |
| 180 | Gate 2 | −5 | +10 |
| 250 | Barricade | loses 10 % (2–5) | |
| 315 | Gate 3 | ×2 | +15 |
| 395 | Gate 4 | −10 | ×3 |
| 446 | Boss entrance | | |

Best path 5 → 15 → 25 → 22 → 44 → **132**; alternative good paths end at 90–110.
Good options alternate sides, so every gate is a steering decision. (The spec's Gate 2 "+15" was
tuned to +10 so the best path stays under the 150 performance cap.)
Boss: 100 HP, damage/second = `4 + 0.14 × crowd` (×2.5 after 9 s), swing every 2.4 s knocks back
`9 %` of the crowd (2–10) but never below 3 survivors, so reaching the boss always means winning.

## 7. How touch input works

`project.godot` enables *emulate touch from mouse*, so desktop mouse drags arrive as the same
`InputEventScreenTouch`/`InputEventScreenDrag` events as on Android. The first finger that touches
anywhere (outside UI buttons) owns steering; each drag adds `relative.x / screen_width × 13` world units
to the target X (a full-width swipe ≈ one road width), clamped to the road for the current formation
width. The crowd centre follows the target through a critically damped spring (`steer_omega = 8.5`),
which gives the weighted "steering a mass" feel; runners follow their slots with individual lag and
lean/turn into the motion. A/D or arrow keys also steer for development.

## 8. Run in Godot

1. Install **Godot 4.6** (standard build, no .NET needed).
2. Open Godot → Import → select `project.godot` (first import takes a few seconds).
3. Press **F5**. The game starts directly with the intro.

Debug keys (debug builds only): **F1** reset, **F2** +10, **F3** −10, **F4** jump to boss,
**F5** ×2 effect, **F6** debug overlay (FPS, crowd, active physics actors, draw calls).
Set `Main → debug_tools_enabled = false` to remove them.

Headless smoke tests (optional):
```
godot --headless --path . --fixed-fps 60 -s tools/autoplay_test.gd            # plays to VICTORY, exit 0
godot --headless --path . --fixed-fps 60 -s tools/autoplay_test.gd -- worst   # picks bad gates → FAILED
godot --headless --path . -s tools/perf_test.gd                               # crowd CPU benchmark
```

## 9. Export to Android

1. Editor → **Editor Settings → Export → Android**: set the Java SDK path (JDK 17) and Android SDK path.
2. **Project → Install Android Build Template** is *not* required (the preset uses the prebuilt template).
3. **Editor → Manage Export Templates** → download templates for 4.6.
4. **Project → Export → Android** (preset already provided): set a keystore for release
   (debug keystore is used automatically for debug exports), then *Export Project* → `export/CrowdRush.apk`,
   or use the one-click deploy button with a USB-debugging device connected.
   Orientation comes from `display/window/handheld/orientation = sensor landscape`; immersive mode is on;
   no permissions are requested (not even INTERNET).

### Build the APK on GitHub (no local setup)

The workflow `.github/workflows/android-apk.yml` builds the APK in GitHub Actions and publishes it as a
**GitHub Release**:

1. GitHub → **Actions** → **Build Android APK** → **Run workflow**.
2. Enter a version name (e.g. `0.1.0`) → **Run workflow**. A build takes about 5–10 minutes (faster once Godot is cached).
3. When it finishes, open **Releases** (right side of the repo page): release `v0.1.0` has
   `CrowdRush-v0.1.0.apk` attached. Download it on your phone and install it
   (allow "Install unknown apps" when asked). The APK is also kept as a workflow artifact for 14 days.

Running it again with the same version name updates that release; use a new version name for a new release.
The Android `versionCode` is the workflow run number, so it always increases.

**Signing (recommended once):** without secrets, each build is signed with a new throwaway key, so Android
refuses to install it *over* the previous build — uninstall first. To sign every build with the same key,
create a keystore once and add three repository secrets (**Settings → Secrets and variables → Actions**):

```
keytool -genkeypair -v -keystore crowdrush.keystore -alias crowdrush -keyalg RSA -keysize 2048 -validity 10000
base64 -w0 crowdrush.keystore        # on macOS: base64 -i crowdrush.keystore
```

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the base64 output |
| `ANDROID_KEYSTORE_ALIAS` | `crowdrush` |
| `ANDROID_KEYSTORE_PASSWORD` | the password you chose |

Keep the keystore file safe and never commit it — you need the same key for all future updates
(and for Google Play).

The same build runs locally with `tools/ci/build_android.sh` (see the variables at the top of the script).

## 10. Performance notes

* **Crowd CPU** (desktop core, `tools/perf_test.gd`): 5 → 0.03 ms, 80 → 0.42 ms, 150 → 0.72 ms per frame
  (150 celebrating with uncached poses: 1.25 ms). Expect roughly 3–5× on mid-range Android.
* **Draw calls**: whole crowd 8 (+shadow), each building type/prop type is one MultiMesh; ~120–160 draw
  calls in the busiest shots including shadows, UI and particles.
* One directional light, 2-split shadows limited to 70 units, 2048 shadow map, no SSAO/SSR/SDFGI/volumetrics,
  cheap exponential fog, light glow. MSAA 2×.
* Physics: at most 24 runner actors + ~12 barricade/prop bodies + the hammer; everything is frozen or pooled
  when idle. Jolt runs at 60 Hz.
* Particles are CPUParticles3D pools (≤140 particles per burst, confetti only at the end).
* All materials are three tiny shaders sharing vertex-coloured meshes — no textures except a 64×64 gradient.
* Knobs if a device struggles: `EnvironmentBuilder.enable_shadows`, `CrowdManager.cast_shadows`,
  `MAX_CROWD`, MSAA, `PhysicsActorPool.pool_size`.
* The shaders branch on `CURRENT_RENDERER`, so the project also renders correctly on the Compatibility
  renderer as a fallback for very old GPUs.

## 11. Exact list of assets used

* **Font**: Lilita One (`assets/fonts/LilitaOne-Regular.ttf`), SIL Open Font License 1.1 (`OFL.txt`).
* **Sounds & music**: 26 WAV files in `assets/sounds/`, all synthesized by `tools/generate_sounds.py`
  (no third-party audio): intro_rumble, city_ambience, whoosh, impact_distant, footstep, footsteps_loop,
  gate_positive, gate_negative, multiply, pop, sparkle, wood_impact, barrier_crash, thud, boss_roar,
  boss_step, weapon_swing, ground_slam, hit, boss_hit, victory_sting, crowd_cheer, ui_click, warning,
  music_main (132 BPM loop), music_boss (140 BPM loop).
* **Everything else is procedural**: runners, boss, buildings, props, cars, gates, barricades, arena,
  clouds (built by `MeshFactory` with SurfaceTool), sky (ProceduralSkyMaterial), particles and the
  soft-circle sprite (GradientTexture2D), icon.svg (hand-written).

## 12. Assumptions

* The intro's "5 → 10 at the ×2 gate" beat is shown with a separate **preview squad** at Gate 1 so the
  player still really starts with exactly 5 and makes the Gate 1 choice themselves.
* The distant-boss reveal uses a telephoto zoom (FOV 58 → 4.2) and briefly thins the fog.
* Characters are animated procedurally (no skeletons/AnimationPlayer); the named states exist in
  `RunnerRig.Anim`, TURN_LEFT/TURN_RIGHT are the additive lean driven by steering.
* Replays skip the intro (session only); the first launch always plays it.
* "Best" is saved locally in `user://crowd_rush_save.cfg` (ConfigFile).
* Gate 2's positive option was tuned from +15 to +10 (see §6); the final crowd typically lands at 80–130.
* Sounds are placeholders designed to be replaced file-for-file by real recordings.
