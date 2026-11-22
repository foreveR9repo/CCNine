# CCNine

Tweak jailbreak **rootless** (Theos / Logos) : remplace le Control Center natif d'iOS 16–17
par une reproduction de celui d'**iOS 9**, avec un vrai flou temps réel (`UIVisualEffectView`).

- Cible : iOS 16–17, `arm64` / `arm64e`, Dopamine 3.0 (testé visé : iPhone SE 2020)
- Geste : swipe depuis le bord inférieur
- ⚠️ Code **non testé sur appareil** : plusieurs API privées sont à valider (voir ci-dessous)

## Compiler avec GitHub Actions

1. Crée un dépôt GitHub et pousse tout ce dossier à la racine (le dossier `.github/` doit être présent).
2. Onglet **Actions** → workflow **Build CCNine (rootless)** (il se lance au premier push).
3. Une fois terminé, ouvre l'exécution → section **Artifacts** → télécharge **CCNine-deb**.
4. Dézippe : tu obtiens `com.example.ccnine_1.0.0_iphoneos-arm64.deb`.

Pour une Release automatique : `git tag v1.0.0 && git push --tags` (le .deb est attaché à la Release).

## Installer

Copie le `.deb` sur l'iPhone, ouvre-le avec Filza / Sileo (« Installer »), puis respring.

## Désactivation d'urgence (respring loop)

Crée ce fichier (SSH ou Filza) puis respring :

    /var/mobile/Library/Preferences/com.example.ccnine.disable

Le tweak se désactive aussi tout seul après 4 chargements en moins de 60 s.
Supprime ce fichier pour le réactiver. Le mode sans échec de Dopamine fonctionne aussi.

## Icônes iOS 9 (optionnel)

Dépose des PNG dans `layout/Library/Application Support/CCNine/` (`airplane.png`, `wifi.png`,
`bluetooth.png`, `moon.fill.png`, `lock.rotation.png`, …). Ils sont chargés en priorité sur les SF Symbols.

## À vérifier sur ta version exacte d'iOS

- Sélecteurs `SBControlCenterController` (`_showControlCenterGesture…`, `isPresented`, `isVisible`)
- `SBHomeHardwareButtonActions performSinglePressUpActions`
- API Focus / Ne pas déranger (`DNDModeAssertionService`) et `CBBlueLightClient` (Night Shift)
- Niveau de fenêtre (`UIWindowLevelAlert + 1000`)

## Fichiers

| Fichier | Rôle |
|---|---|
| `Tweak.x` | Hooks (CC natif, bouton Home), garde-fous anti respring-loop |
| `CC9ViewController.m` | Fenêtre, panneau iOS 9, flou, geste interactif |
| `CC9Controls.m` | Boutons ronds, sliders, icônes |
| `CC9Backend.m` | Wi-Fi, Bluetooth, avion, DND, rotation, luminosité, volume, média |
