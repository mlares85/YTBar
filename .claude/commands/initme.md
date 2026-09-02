# Session Initialization

You are starting a new session on YTBar. Follow these steps to get oriented:

## 1. Load Soft Context

Read `docs/activeContext.md` — focus on the STATUS header and newest log entry, not the whole file.

## 2. Load Architecture Context

If `ARCHITECTURE.md` exists, grep it for tags matching your work area (e.g. `[player]`, `[api]`, `[yt-dlp]`). Read matching lines, not the whole file.

Available tags: `[api]`, `[player]`, `[auth]`, `[cache]`, `[ui]`, `[build]`, `[yt-dlp]`

## 3. Check Recent Work

Run: `git log --oneline -15`

## 4. Check Test Health

Run: `swift test 2>&1 | tail -10`

If tests fail, note which ones and include in the summary.

## 5. Check Implementation Status

Compare specs against implementations:
- List spec files: `ls docs/specs/*.md 2>/dev/null`
- Check for matching source implementations in `Sources/`
- For each spec, note whether it has a corresponding implementation

## 6. Present Summary

Format your summary as:

```
## Session Start

**Current Focus**: [from activeContext.md]

**Recent Work** (git log):
- [last 5-8 commits, summarized]

**Test Status**: [pass/fail/none] ([N] tests)

**Architecture Notes**: [any relevant ARCHITECTURE.md entries for current focus area]

**Implementation Progress**:
- [ ] [feature name] (spec: docs/specs/[name].md)
[check boxes for specs that have matching implementations]

**Blockers**: [from activeContext.md, or "None"]

**Next Steps**:
1. [from activeContext.md]
2. [from activeContext.md]
3. [from activeContext.md]
```

After presenting the summary, ask: "Ready to continue, or do you want to adjust the focus?"
