// functions/src/notifyFollowedCategory.ts
import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { getMessaging } from 'firebase-admin/messaging';

// General/editorial notifications are explicitly out of scope and stay
// free (spec) — this only ever fires for a contribution transitioning
// INTO approved, never for editorial POI/guide/news publishes (a
// different content pipeline entirely, unaffected by this function).
//
// getMessaging().send() signature verified against the resolved
// firebase-admin v13.10.0 package (functions/node_modules/firebase-admin/
// lib/messaging/messaging.d.ts and messaging-api.d.ts): `send(message:
// Message, dryRun?: boolean): Promise<string>`, where `Message` is a union
// including `TopicMessage extends BaseMessage { topic: string }` and
// `BaseMessage` carries an optional `notification?: { title?: string;
// body?: string; imageUrl?: string }`. The `{ topic, notification: { title,
// body } }` shape below matches that union exactly.
export const notifyFollowedCategory = onDocumentUpdated(
  { region: 'europe-west1', document: 'contributions/{contributionId}' },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.status === 'approved' || after.status !== 'approved') return;
    if (after.shadowHidden === true) return; // never notify about a shadow-hidden spot

    const category = after.category as string | undefined;
    if (!category) return;

    await getMessaging().send({
      topic: `spots-${category}`,
      notification: {
        // Placeholder, unlocalized push copy — a genuine, disclosed
        // simplification for this task. FCM notification payloads are
        // plain strings sent from the server, not String Catalog keys
        // resolved on-device; proper localization of push copy requires
        // either sending pre-localized text per recipient (needs
        // per-user language stored server-side) or Apple's
        // `loc-key`/`loc-args` APNs mechanism (which FCM does support
        // passing through, but requires the exact right payload shape).
        // Flagged as a known gap for a follow-up rather than
        // half-implementing localized push here.
        title: 'New spot in a category you follow',
        body: after.title as string,
      },
    });
  }
);
