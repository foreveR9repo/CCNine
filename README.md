# CCNine

**Rootless** jailbreak tweak (Theos / Logos): replaces the native iOS 15–17 Control Center with a recreation of the **iOS 9** Control Center, featuring real-time blur (`UIVisualEffectView`).

- Target: iOS 15–17, `arm64` / `arm64e`, rootless jailbreaks (Dopamine, palera1n rootless…) (tested/targeted: iPhone SE 2020)
- Gesture: swipe up from the bottom edge
- Code Tested: Everything works since version 0.10.1

## Files

| File | Role |
|---|---|
| `Tweak.x` | Hooks (native CC, Home button), respring-loop guards |
| `CC9ViewController.m` | Window, iOS 9 panel, blur, interactive gesture |
| `CC9Controls.m` | Round buttons, sliders, icons |
| `CC9Backend.m` | Wi-Fi, Bluetooth, Airplane mode, DND, orientation lock, brightness, volume, media |
