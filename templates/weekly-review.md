# Weekly Review

Use this review to keep the workspace healthy.

## Handoff Health

- Are handoff files short enough to bootstrap a session?
- Did any handoff become a chronological history dump?
- Are required sections present?
- Does each handoff have a concrete next step?

## Ops Log Health

- Does `_ops_log/agent_action_log.jsonl` parse line by line?
- Are there blank lines, BOM, NUL bytes, or malformed JSON lines?
- Do audit-worthy changes include rollback hints?

## Rules Health

- Are any rules stale or contradicted by current practice?
- Did repeated feedback reveal a new stable rule?
- Should any rule move into an ADR instead?

## Decision Health

- Which pending decisions need owners?
- Which decisions should become ADRs?
- Which ADRs need revisit because assumptions changed?

## Attention Health

- Does `00_THIS_WEEK.md` reflect the real priority system?
- Are agents chasing recently modified files instead of current priorities?
- What should move to next week?

## Learning Candidates

| Observation | Should Become | Owner | Next Step |
| --- | --- | --- | --- |
| Example repeated issue | Rule / SOP / ADR / next-week task | lead | Draft update |
