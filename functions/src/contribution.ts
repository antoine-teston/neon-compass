// Pure validation for submitContribution's input — kept separate from the
// onCall wrapper so it's unit-testable with plain node:test, no emulator
// needed. Mirrors handle.ts's pattern (pure function + separate CF file).

export const ALLOWED_CATEGORIES = ['landmark', 'collectible', 'activity', 'safehouse', 'vehicle', 'event'] as const;
export type ContributionCategory = (typeof ALLOWED_CATEGORIES)[number];

export const ALLOWED_LANGUAGES = ['en', 'fr', 'es', 'it', 'de'] as const;
export type ContributionLanguage = (typeof ALLOWED_LANGUAGES)[number];

export interface SubmissionInput {
  category: ContributionCategory;
  title: string;
  position: { x: number; y: number };
  languageCode: ContributionLanguage;
}

const MAX_TITLE_LENGTH = 280;

// Deliberately basic: schema/length/range validation only. The spec's full
// anti-abuse layer (App Check, cooldown, geo-dedup, vocabulary filter,
// velocity monitoring) is Plan 5c, not here — see this plan's Global
// Constraints.
export function validateSubmission(input: unknown): SubmissionInput {
  if (typeof input !== 'object' || input === null) {
    throw new Error('Submission must be an object.');
  }
  const record = input as Record<string, unknown>;

  const category = record.category;
  if (typeof category !== 'string' || !ALLOWED_CATEGORIES.includes(category as ContributionCategory)) {
    throw new Error(`category must be one of: ${ALLOWED_CATEGORIES.join(', ')}`);
  }

  const title = record.title;
  if (typeof title !== 'string') {
    throw new Error('title must be a string.');
  }
  const trimmedTitle = title.trim();
  if (trimmedTitle.length === 0 || trimmedTitle.length > MAX_TITLE_LENGTH) {
    throw new Error(`title must be 1-${MAX_TITLE_LENGTH} characters.`);
  }

  const position = record.position;
  if (typeof position !== 'object' || position === null) {
    throw new Error('position must be an object with x/y.');
  }
  const { x, y } = position as Record<string, unknown>;
  if (typeof x !== 'number' || typeof y !== 'number' || x < 0 || x > 1 || y < 0 || y > 1) {
    throw new Error('position.x and position.y must be numbers in [0, 1].');
  }

  const languageCode = record.languageCode;
  if (typeof languageCode !== 'string' || !ALLOWED_LANGUAGES.includes(languageCode as ContributionLanguage)) {
    throw new Error(`languageCode must be one of: ${ALLOWED_LANGUAGES.join(', ')}`);
  }

  return {
    category: category as ContributionCategory,
    title: trimmedTitle,
    position: { x, y },
    languageCode: languageCode as ContributionLanguage,
  };
}
