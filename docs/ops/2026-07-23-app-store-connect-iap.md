# App Store Connect: In-App Purchase & Server Notifications setup (manual steps)

Not expressible in code — App Store Connect configuration. Spec §"Pro":
"achat unique ~5-6 €, StoreKit 2".

## 1. Create the Pro IAP product

1. App Store Connect → this app → In-App Purchases → Create.
2. Type: Non-Consumable.
3. Product ID: `co.antoineteston.neoncompass.pro` (must match
   `StoreKitProProvider.proProductID` exactly — update both if this
   changes).
4. Price: ~5-6 € tier (spec-suggested range).
5. Add a `.storekit` local testing configuration in Xcode (Product Data →
   New File → StoreKit Configuration) with a matching test product, so the
   paywall can be exercised in the Simulator without a live App Store
   Connect roundtrip. None exists in this project yet.

## 2. Configure App Store Server Notifications V2

1. App Store Connect → this app → App Information → App Store Server
   Notifications.
2. Version: V2.
3. Production/Sandbox URL: the deployed `appStoreServerNotification`
   Cloud Function's HTTPS trigger URL (`https://europe-west1-<project>.
   cloudfunctions.net/appStoreServerNotification`).

## 3. Environment variables required at deploy time

`functions/src/appStoreServerNotification.ts` reads three environment
variables — none have a safe default for production:

- `APP_STORE_ENVIRONMENT` — `"sandbox"` for TestFlight/local testing,
  anything else (including unset) defaults to production. Get this wrong
  and every genuinely-signed sandbox notification fails verification.
- `APP_BUNDLE_ID` — must exactly match the shipped app's bundle ID.
  **Currently falls back to a placeholder (`com.neoncompass.app`) if
  unset — this is NOT this app's real bundle ID** (see `project.yml`'s
  `bundleIdPrefix: co.antoineteston`). Failing to set this explicitly at
  deploy time means every real notification fails signature verification
  (fails closed — no security hole, but a total availability outage for
  the badge mirror). Set explicitly before any production deploy.
- `APP_STORE_APPLE_ID` — the app's numeric Apple ID, required only when
  `APP_STORE_ENVIRONMENT` is production (the library requires it in that
  case). Find it in App Store Connect → App Information.

## 4. Link a purchase to an account (opt-in, badge only)

`appAccountToken` must be attached client-side at purchase time for the
server mirror to do anything — the webhook (Task 5) already handles a
missing token gracefully (a normal, expected no-op, since "l'achat ne
requiert jamais de connexion"), but as of this plan **no client code
attaches one yet**. `StoreKitProProvider.purchase()` calls
`product.purchase()` with no purchase options.

This is a real, deliberate gap between Task 5's webhook and the client's
purchase call — flagging it here rather than silently shipping half the
mirror. To close it, a follow-up must add:
1. A `appAccountToken: UUID` field on the profile doc, generated once at
   profile creation (`createUserProfile.ts`, Plan 5) and written to
   Firestore.
2. `StoreKitProProvider.purchase()` reading that UUID (would need a new
   parameter, since this file currently has zero Firebase/account
   dependency by design) and passing
   `product.purchase(options: [.appAccountToken(profileUUID)])`.

Until this follow-up lands, the Pro badge on the profile screen will
never populate even for a real signed-in purchaser — the purchase itself,
ad removal, and every on-device Pro feature are entirely unaffected,
since none of them read `isPremium` (see this plan's Global Constraints).
