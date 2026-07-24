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

**Correction (found during this task's review, verified empirically against
this project's exact Xcode/SDK version by building a minimal test project
with `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` pointed at a
nonexistent icon set):** the original version of this doc claimed `actool`
fails the build if the referenced icon set is missing. That's wrong —
`actool` degrades gracefully: a nonexistent alternate-icon name is silently
dropped from the synthesized `CFBundleIcons`, with zero errors or warnings,
and the build succeeds regardless. So the build setting genuinely could be
added now, safely, without waiting for the asset — this project's precedent
for "harmless-if-unresolved" additions (like `GADApplicationIdentifier`)
does extend to this case too, contrary to what this doc originally implied.

**A bigger, separate, pre-existing gap found during the same review:** this
project has **no `Assets.xcassets` catalog at all yet** — not just no
`AppIcon-Neon`, but no primary `AppIcon` either. That's out of this task's
scope to fix (it predates Plan 6b-2 entirely), but it means the
`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` build setting has nothing to
attach to structurally until an asset catalog exists at all, not just until
the alternate icon specifically is designed.

**Decision:** this build setting is still left out of `project.yml` for
now — not because adding it would break the build (it wouldn't), but simply
because it would be inert until an asset catalog (and the primary `AppIcon`
within it) exists in the first place. `NCTheme.swift` and
`ThemeStore.setAlternateIcon(named:)` were still wired (Swift compiles fine
against an icon-set *name* string — it's only resolved at runtime by UIKit,
not at compile time), and the Profile UI's icon picker calls that method
assuming `AppIcon-Neon` will exist eventually. Until the steps below are
done, tapping the icon picker in a build will silently no-op
(`setAlternateIconName` fails via its completion handler; UIKit has no
`CFBundleAlternateIcons` entry to switch to).

## 1. Create the asset catalog + icon sets (human/designer follow-up)

1. Create `NeonCompass/Resources/Assets.xcassets` — this project doesn't
   have one yet at all, so this also needs to include a primary `AppIcon`
   entry, not just the alternate.
2. Design a full icon set (all required sizes) as original artwork — no
   Rockstar/GTA imagery, per this project's hard IP constraint (CLAUDE.md).
3. Add the alternate as a **separate** "App Icon" asset catalog entry named
   `AppIcon-Neon` (not the primary `AppIcon`).
4. Add to `project.yml`, under `targets.NeonCompass.settings.base`:
   ```yaml
   ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES: AppIcon-Neon
   ```
   (Space-separate multiple names if more themed icons are added later. Per
   the correction above, this line is safe to add in the same PR that adds
   the assets — it doesn't need to be staged separately out of caution.)
5. Regenerate the Xcode project (`xcodegen generate` or via `Scripts/build.sh`
   if it does so) and confirm `Scripts/build.sh` still succeeds.

## 2. Verify in TestFlight

Alternate icon switching (`UIApplication.setAlternateIconName`) only takes
visible effect on a real device/TestFlight build, not reliably in the
Simulator — verify the icon actually changes on the home screen with a
physical device before shipping.
