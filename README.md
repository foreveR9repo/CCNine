# CCNine

**Rootless** jailbreak tweak (Theos / Logos): replaces the native iOS 15–17 Control Center with a recreation of the **iOS 9** Control Center, featuring real-time blur (`UIVisualEffectView`).

- Target: iOS 15–17, `arm64` / `arm64e`, rootless jailbreaks (Dopamine, palera1n rootless…) (tested/targeted: iPhone SE 2020)
- Gesture: swipe up from the bottom edge
- Code **Tested**: Everything works since version 0.10.1

## Files

| File | Role |
|---|---|
| `Tweak.x` | Hooks (native CC, Home button), respring-loop guards |
| `CC9ViewController.m` | Window, iOS 9 panel, blur, interactive gesture |
| `CC9Controls.m` | Round buttons, sliders, icons |
| `CC9Prefs.m` | Reads the Settings values (live, via Darwin notification) |
| `ccninepref/` | Settings bundle (PreferenceLoader) |
| `CC9Backend.m` | Wi-Fi, Bluetooth, Airplane mode, DND, orientation lock, brightness, volume, media |

## Settings (Settings > CCNine)

| Option | Effect |
|---|---|
| Screen Recording instead of Calculator | Replaces the Calculator shortcut with a Screen Recording button (uses the native ReplayKit Control Center module; the panel closes when recording starts) |
| Whitening | White veil over the blur, 0–90 % (default 30 %) |
| Reset to defaults | Restores both options |

Requires `preferenceloader`. Settings are stored in `com.example.ccnine` and applied live (no respring).

If screen recording does nothing, send `/var/mobile/Documents/CCNine_log.txt` (lines starting with `SR:`).
