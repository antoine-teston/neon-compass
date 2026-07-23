export type VoteDirection = 'up' | 'down';

export interface VoteDelta {
  upvoteDelta: number;
  downvoteDelta: number;
}

// Re-voting the same direction overwrites the same vote document with no
// count change (spec: "revoter réécrit le même document"). Switching
// direction moves one vote from one bucket to the other.
export function applyVoteDelta(previous: VoteDirection | null, next: VoteDirection): VoteDelta {
  if (previous === next) {
    return { upvoteDelta: 0, downvoteDelta: 0 };
  }
  if (previous === null) {
    return next === 'up' ? { upvoteDelta: 1, downvoteDelta: 0 } : { upvoteDelta: 0, downvoteDelta: 1 };
  }
  // previous is the other direction than next
  return next === 'up' ? { upvoteDelta: 1, downvoteDelta: -1 } : { upvoteDelta: -1, downvoteDelta: 1 };
}
