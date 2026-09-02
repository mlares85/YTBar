# Mandatory Update Protocol (MUP)

Run this at the end of every session to preserve context for the next one.

## 1. Review What Was Done

Run: `git log --oneline -10`

## 2. Check Test Status

Run: `swift test 2>&1 | tail -10`

## 3. Update `docs/activeContext.md`

Rewrite the file with fresh content:

- **Current Focus**: What the next session should pick up (1-2 lines)
- **Recent Decisions**: Any decisions made this session with brief rationale. Only include things git log doesn't capture (the "why", not the "what"). Drop decisions from previous sessions that are no longer relevant.
- **Blockers / Open Questions**: Anything unresolved that the next session needs to know about
- **Next Steps**: Top 3 priorities for the next session, ordered by importance

Rules:
- Keep the file under 50 lines total
- If it would exceed 50 lines, archive older decisions to `docs/activeContext.archive.md` before trimming
- Do NOT list files modified or implementation status — git log and `/initme` handle that
- Be specific and actionable, not vague

## 4. Update `ARCHITECTURE.md`

Review the session's work and update `ARCHITECTURE.md`:

- **Add** any new non-obvious patterns, constraints, or workarounds discovered this session as tagged single-line bullets (e.g. `- [player] AVPlayer does X because Y`)
- **Prune** entries whose root cause was fixed — stale entries are worse than none
- **Mark** workarounds with `WORKAROUND:` so they're findable and fileable later
- Keep entries to 1-2 sentences max
- Use existing tags: `[api]`, `[player]`, `[auth]`, `[cache]`, `[ui]`, `[build]`, `[yt-dlp]`

## 5. Commit the Update

Stage and commit the context files:

```bash
git add docs/activeContext.md ARCHITECTURE.md
git commit -m "docs(context): MUP session update"
```

If `docs/activeContext.archive.md` was created or updated, include it in the commit too.

## 6. Confirm

Report: "MUP complete. Context saved for next session." and show the updated activeContext.md content.
