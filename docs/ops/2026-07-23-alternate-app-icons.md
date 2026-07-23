# Alternate App Icons — asset & App Store Connect steps (manual)

Not expressible in code beyond the `ThemeStore.setAlternateIcon(named:)` call
(Plan 6b-2, Task 5). Spec §"Pro": "Icônes d'app... exclusifs."

## Why `project.yml` was NOT touched in Task 5

Researched XcodeGen's mechanism for declaring alternate icons before writing
any config (per this project's established discipline — see the
`GADApplicationIdentifier`/`Info-Ads.plist` precedent from Plan 6a Task 1).

**Finding:** XcodeGen has no dedicated "icon set" declaration in its project
spec (no `icon:`/`alternateIcons:` key). The current (Xcode 13+) mechanism is
a plain build setting:

```yaml
ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES: AppIcon-Neon
```

When `GENERATE_INFOPLIST_FILE: YES` is set (as it is here), Xcode's asset
catalog compiler (`actool`) reads this build setting and *automatically*
synthesizes the `CFBundleIcons`/`CFBundleIcons~ipad` dictionary (primary +
alternate icon entries) into the generated Info.plist at build time. This is
different from `GADApplicationIdentifier` (Plan 6a Task 1): that key has no
`INFOPLIST_KEY_*` synthesis path at all, so it required a hand-merged
`Info-Ads.plist` via `INFOPLIST_FILE`. Alternate icons instead have a
first-class build-setting path — no manual Info.plist merge needed once the
asset exists.

**The catch:** `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` requires each
named icon set (e.g. `AppIcon-Neon`) to actually exist as a separate "App
Icon" asset catalog entry in `Assets.xcassets`. Unlike a plain Info.plist
string key (which can reference a nonexistent name without breaking
compilation), this is a build setting consumed by `actool`, which fails the
build if the referenced icon set is missing.

**Decision:** since no alternate icon asset exists yet (confirmed — this
plan has no image-generation capability), this build setting was
**deliberately left out of `project.yml`** to keep `Scripts/build.sh` green.
`NCTheme.swift` and `ThemeStore.setAlternateIcon(named:)` were still wired
(Swift compiles fine against an icon-set *name* string — it's only resolved
at runtime by UIKit, not at compile time), and the Profile UI's icon picker
calls that method assuming `AppIcon-Neon` will exist eventually. Until the
step below is done, tapping the icon picker in a build will silently no-op
(`setAlternateIconName` fails via its completion handler; UIKit has no
`CFBundleAlternateIcons` entry to switch to).

## 1. Create the icon asset (human/designer follow-up)

1. Design a full icon set (all required sizes) as original artwork — no
   Rockstar/GTA imagery, per this project's hard IP constraint (CLAUDE.md).
2. Add it to `NeonCompass/Resources/Assets.xcassets` as a **separate** "App
   Icon" asset catalog entry named `AppIcon-Neon` (not the primary
   `AppIcon`).
3. Add to `project.yml`, under `targets.NeonCompass.settings.base`:
   ```yaml
   ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES: AppIcon-Neon
   ```
   (Space-separate multiple names if more themed icons are added later.)
4. Regenerate the Xcode project (`xcodegen generate` or via `Scripts/build.sh`
   if it does so) and confirm `Scripts/build.sh` still succeeds — this is the
   point where a missing/misnamed asset would first surface as a build
   failure.

## 2. Verify in TestFlight

Alternate icon switching (`UIApplication.setAlternateIconName`) only takes
visible effect on a real device/TestFlight build, not reliably in the
Simulator — verify the icon actually changes on the home screen with a
physical device before shipping.
