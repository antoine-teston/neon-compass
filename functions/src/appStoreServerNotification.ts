// App Store Server Notifications V2 webhook (Plan 6b-1, Task 5).
//
// Best-effort account badge mirror ONLY — never read by any client-side or
// server-side gating logic (see this plan's Global Constraints). Pro
// entitlement gating stays purely on-device via StoreKit's own transaction
// verification. If this function is ever down, misconfigured, or a profile
// has no matching appAccountToken yet, the worst outcome is a stale/missing
// `isPremium` badge on the profile screen — never a broken feature.
//
// Package research (this task): the brief's sketch guessed the import path
// `@apple/app-store-server-library` and an unverified `SignedDataVerifier`
// API. Confirmed via npm + the installed package's own .d.ts files
// (node_modules/@apple/app-store-server-library@3.1.0/dist/jws_verification.d.ts):
//   - Real package name: `@apple/app-store-server-library` (the brief's guess
//     was correct on the name; npm also lists an unrelated third-party
//     `app-store-server-api` package — do not confuse the two).
//   - `new SignedDataVerifier(appleRootCertificates: Buffer[], enableOnlineChecks:
//     boolean, environment: Environment, bundleId: string, appAppleId?: number)`.
//     `appAppleId` is required when `environment` is PRODUCTION.
//   - Apple's root certificates are NOT bundled by the library — its own
//     README says to download the DER-encoded certs from
//     https://www.apple.com/certificateauthority/ and pass them in yourself.
//     We vendor `AppleRootCA-G3.cer` (the root that signs the current App
//     Store Server Notification chain) at functions/certs/ and read it with
//     fs at call time.
//   - Deviation from the brief's sketch: `data.signedTransactionInfo` is
//     itself a signed JWS *string*, not an already-decoded object — the
//     brief's `transactionInfo?.appAccountToken` would have read a field off
//     a raw JWT string and always been `undefined`. It must be verified and
//     decoded separately via `verifier.verifyAndDecodeTransaction(...)`.
//   - Deviation from the brief's sketch: the brief's entitlement check
//     (`subtype` in `['SUBSCRIBED', 'DID_RENEW']`) assumes an auto-renewable
//     subscription. Per this project's spec
//     (docs/superpowers/specs/2026-07-19-neon-compass-companion-design.md,
//     "Pro one-shot 5,99 €"), Pro is a one-time non-consumable purchase, not
//     a subscription — `subtype` is not populated for `ONE_TIME_CHARGE` at
//     all. The correct signal is `notificationType`: `ONE_TIME_CHARGE` grants
//     the entitlement; `REFUND`/`REVOKE` (e.g. Family Sharing revocation)
//     withdraw it. Every other notification type (TEST, CONSUMPTION_REQUEST,
//     etc.) is not relevant to this one-time product and is ignored.
import { onRequest } from 'firebase-functions/v2/https';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { Environment, SignedDataVerifier } from '@apple/app-store-server-library';

// process.env.APP_STORE_ENVIRONMENT (set at deploy time) distinguishes
// TestFlight/sandbox from production; App Store notifications from Apple's
// sandbox (used for TestFlight/local testing) must be verified against
// Environment.SANDBOX rather than PRODUCTION, or verification fails even
// for a genuinely-signed sandbox payload.
const APP_STORE_ENVIRONMENT =
  process.env.APP_STORE_ENVIRONMENT === 'sandbox' ? Environment.SANDBOX : Environment.PRODUCTION;

// Bundle ID must match the shipped app exactly — verification fails
// otherwise. This is intentionally read from an env var rather than
// hardcoded so staging/production can differ without a code change; see
// functions ops doc (Plan 6b-1 Task 6) for how this is set at deploy time.
const BUNDLE_ID = process.env.APP_BUNDLE_ID ?? 'com.neoncompass.app';

// Required by the library only when targeting PRODUCTION; undefined is
// correct (and expected) for SANDBOX.
const APP_APPLE_ID = process.env.APP_STORE_APPLE_ID ? Number(process.env.APP_STORE_APPLE_ID) : undefined;

const __dirname = dirname(fileURLToPath(import.meta.url));

// Called lazily on first request (from getVerifier(), which caches the
// resulting SignedDataVerifier) rather than at module load — the
// certificate file never changes at runtime, so it's still only ever
// read once per function instance; re-reading it on every invocation
// would be wasted I/O under load.
function loadAppleRootCertificates(): Buffer[] {
  // Vendored from https://www.apple.com/certificateauthority/ — see this
  // file's header comment. Resolved relative to the compiled lib/ output
  // (../certs is a sibling of lib/ under functions/), not the source tree.
  const certPath = join(__dirname, '..', 'certs', 'AppleRootCA-G3.cer');
  return [readFileSync(certPath)];
}

let cachedVerifier: SignedDataVerifier | undefined;
function getVerifier(): SignedDataVerifier {
  if (!cachedVerifier) {
    // Online checks (revocation + expiry against current time) require
    // outbound network access from the Cloud Function, which is available
    // in this runtime — enabled for defense in depth against a compromised
    // or expired intermediate certificate.
    cachedVerifier = new SignedDataVerifier(
      loadAppleRootCertificates(),
      true,
      APP_STORE_ENVIRONMENT,
      BUNDLE_ID,
      APP_APPLE_ID
    );
  }
  return cachedVerifier;
}

// Notification types that grant vs. withdraw the Pro entitlement for our
// one-time, non-consumable "Pro" product. Every other notification type
// (TEST pings, CONSUMPTION_REQUEST, subscription-only types, etc.) is
// irrelevant to this product and left unhandled below.
const GRANT_TYPES = new Set(['ONE_TIME_CHARGE']);
const REVOKE_TYPES = new Set(['REFUND', 'REVOKE']);

export const appStoreServerNotification = onRequest({ region: 'europe-west1' }, async (req, res) => {
  const signedPayload = req.body?.signedPayload;
  if (typeof signedPayload !== 'string') {
    res.status(400).send('missing signedPayload');
    return;
  }

  // Verify the JWS signature against Apple's certificate chain before
  // trusting anything in the payload — never parse an unverified JWT.
  let decodedPayload;
  try {
    decodedPayload = await getVerifier().verifyAndDecodeNotification(signedPayload);
  } catch (error) {
    logger.warn('appStoreServerNotification: signature verification failed', error);
    res.status(400).send('invalid signature');
    return;
  }

  const notificationType = decodedPayload.notificationType;
  const isGrant = typeof notificationType === 'string' && GRANT_TYPES.has(notificationType);
  const isRevoke = typeof notificationType === 'string' && REVOKE_TYPES.has(notificationType);
  if (!isGrant && !isRevoke) {
    // Not relevant to the one-time Pro entitlement (e.g. a TEST ping) —
    // acknowledge so Apple doesn't retry, but there's nothing to mirror.
    res.status(200).send('notification type not relevant, ignored');
    return;
  }

  // signedTransactionInfo is itself a signed JWS string, not an already
  // -decoded object — it must be independently verified and decoded to
  // reach fields like appAccountToken.
  const signedTransactionInfo = decodedPayload.data?.signedTransactionInfo;
  if (typeof signedTransactionInfo !== 'string') {
    logger.warn('appStoreServerNotification: notification missing signedTransactionInfo', { notificationType });
    res.status(200).send('no transaction info, ignored');
    return;
  }

  let appAccountToken: string | undefined;
  try {
    const transaction = await getVerifier().verifyAndDecodeTransaction(signedTransactionInfo);
    appAccountToken = transaction.appAccountToken;
  } catch (error) {
    logger.warn('appStoreServerNotification: transaction verification failed', error);
    res.status(400).send('invalid transaction signature');
    return;
  }

  if (!appAccountToken) {
    // Purchase made without being signed in — nothing to mirror, not an
    // error (spec: "l'achat ne requiert jamais de connexion"). This is the
    // expected, common case until a future task wires up client-side
    // appAccountToken attachment (see this plan's Task 6 ops doc).
    res.status(200).send('no account token, ignored');
    return;
  }

  const db = getFirestore();
  const matching = await db.collection('profiles').where('appAccountToken', '==', appAccountToken).limit(1).get();
  if (!matching.empty) {
    await matching.docs[0].ref.update({ isPremium: isGrant });
  }

  res.status(200).send('ok');
});
