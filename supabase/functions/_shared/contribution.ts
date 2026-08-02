// Validation pure d'une soumission — portage de functions/src/contribution.ts.
//
// Séparée du gestionnaire HTTP pour la même raison qu'avant : elle se teste avec
// `deno test`, sans base ni runtime. C'est la partie qui décide, le gestionnaire
// ne fait qu'exécuter.

export const ALLOWED_CATEGORIES = [
  'landmark',
  'collectible',
  'activity',
  'safehouse',
  'vehicle',
  'event',
] as const;
export type ContributionCategory = (typeof ALLOWED_CATEGORIES)[number];

export const ALLOWED_LANGUAGES = ['en', 'fr', 'es', 'it', 'de'] as const;
export type ContributionLanguage = (typeof ALLOWED_LANGUAGES)[number];

export interface SubmissionInput {
  category: ContributionCategory;
  title: string;
  positionX: number;
  positionY: number;
  languageCode: ContributionLanguage;
}

const MAX_TITLE_LENGTH = 280;

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
  if (typeof title !== 'string') throw new Error('title must be a string.');
  const trimmedTitle = title.trim();
  if (trimmedTitle.length === 0 || trimmedTitle.length > MAX_TITLE_LENGTH) {
    throw new Error(`title must be 1-${MAX_TITLE_LENGTH} characters.`);
  }

  // Deux scalaires plutôt qu'un objet imbriqué, contrairement à Firestore : la
  // table stocke `position_x`/`position_y`, ce qui rend la déduplication
  // géographique indexable.
  const positionX = record.position_x;
  const positionY = record.position_y;
  if (
    typeof positionX !== 'number' || typeof positionY !== 'number' ||
    positionX < 0 || positionX > 1 || positionY < 0 || positionY > 1
  ) {
    throw new Error('position_x and position_y must be numbers in [0, 1].');
  }

  const languageCode = record.language_code;
  if (typeof languageCode !== 'string' || !ALLOWED_LANGUAGES.includes(languageCode as ContributionLanguage)) {
    throw new Error(`language_code must be one of: ${ALLOWED_LANGUAGES.join(', ')}`);
  }

  return {
    category: category as ContributionCategory,
    title: trimmedTitle,
    positionX,
    positionY,
    languageCode: languageCode as ContributionLanguage,
  };
}

// Liste réduite et curée à la main — même philosophie que les listes de mots des
// pseudonymes. Ce n'est PAS un remplacement de la modération, seulement un
// premier filtre pour que le plus évident n'atteigne jamais un humain.
const BANNED_VOCABULARY = [/\bfuck\b/i, /\bshit\b/i, /\bnigger\b/i, /\bcunt\b/i, /https?:\/\//i];

export function containsBannedVocabulary(text: string): boolean {
  return BANNED_VOCABULARY.some((pattern) => pattern.test(text));
}

export const DEDUP_THRESHOLD_NORMALIZED = 0.02;

/** Distance euclidienne simple : la carte est une image schématique, pas une
 *  projection géographique — rien ici n'appelle une formule de haversine. */
export function isTooCloseToExistingSpot(
  candidate: { x: number; y: number },
  existing: Array<{ x: number; y: number }>,
  thresholdNormalized: number = DEDUP_THRESHOLD_NORMALIZED,
): boolean {
  return existing.some((point) => {
    const dx = point.x - candidate.x;
    const dy = point.y - candidate.y;
    return Math.sqrt(dx * dx + dy * dy) < thresholdNormalized;
  });
}

export const COOLDOWN_SECONDS = 60;
