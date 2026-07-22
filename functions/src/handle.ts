import { randomInt } from 'node:crypto';

// Synthwave-themed word lists — original, never a Rockstar/GTA term.
// Deliberately small and curated (not sourced from any wordlist that could
// leak trademarked names) — extend by hand if variety needs grow.
const ADJECTIVES = ['NEON', 'CHROME', 'RETRO', 'ULTRA', 'MIDNIGHT', 'ELECTRIC', 'TURBO', 'CRIMSON'];
const NOUNS = ['FALCON', 'MIRAGE', 'DRIFTER', 'HORIZON', 'CIRCUIT', 'PANTHER', 'VORTEX', 'RUNNER'];

export function generateHandle(): string {
  const adjective = ADJECTIVES[randomInt(ADJECTIVES.length)];
  const noun = NOUNS[randomInt(NOUNS.length)];
  const number = randomInt(100).toString().padStart(2, '0');
  return `${adjective}-${noun}-${number}`;
}
