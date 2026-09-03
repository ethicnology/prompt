# Review Surface Design

Companion to `agentic-code-review-sota.md`. That document settles the agent protocol: independent passes, structured findings, external oracles, bounded adversarial debate, adjudication, human authority. It does not settle two things this document covers.

1. **What can be reviewed.** Today a review is locked to one session's diff. Branch-to-branch, commit-to-commit and uncommitted work must all become reviewable.
2. **What the review looks and feels like.** The current screen is a set of tabs and lists with the diff hidden behind an `ExpansionTile`. The target is a surface where the diff *is* the interface and where the developer argues with the agents on specific lines.

Research date: 2026-09-02. Sources are cited inline. Nothing here is committed product scope until the open questions at the end are answered.

---

## 1. Why the current module fails

Verified against the code, not impressions.

- `review_screen.dart:664` wraps the whole diff in an `ExpansionTile`, so the diff is collapsed by default. `DiffViewer` already implements per-file collapse and sliver virtualisation (`diff_viewer.dart:16`, `:29-54`), so this outer tile only hides a capable component.
- `ReviewFinding` already carries `file`, `startLine`, `endLine`, `side` (`review_entities.dart:108-111`), and the provider schema enforces all four (`review_result_parser.dart:4-60`). The screen renders the anchor as *text* (`review_screen.dart:629-631`). No code anywhere joins a finding to its diff row.
- `ReviewFindingStatus` has exactly one value, `hypothesis` (`review_entities.dart:31`), and `status` always returns it (`:124`). The product states that every finding is unproven and offers no way to prove or refute one.
- `ReviewExecutionService` exposes only `loadSnapshot`, `createChild`, `runPass`, `abort` (`opencode_review_service.dart:10-24`). A pass is one message and one reply (`:134-222`). Conversation is structurally impossible.
- `DiffRow.id` is a per-file counter (`unified_diff_parser.dart:77`), so a row cannot be addressed from outside the parser.

The capabilities are mostly present. The composition wastes them.

---

## 2. Diff sources

### 2.0 Read the running server's spec, not the published docs

Everything in this section was **executed against the live server on 2026-09-02**, version `1.18.26`, by fetching its own OpenAPI document at `GET /doc` and calling the endpoints. The published documentation at `opencode.ai/docs/server/` and the generated SDK types on the `dev` branch are both **stale**: they omit an entire family of VCS endpoints that the server actually serves. Any future capability question should start from `/doc` on the running instance.

A hypothesis recorded earlier in this document — that our parser expected `patch` and `status` while the API returned `before` and `after`, and that the review module therefore never loaded a snapshot — is **refuted**. The endpoint returns `SnapshotFileDiff`, whose fields are `file`, `patch`, `status`, `additions`, `deletions`. Our parser is correct. The `FileDiff` type carrying `before`/`after` exists in the SDK but is not what this endpoint returns.

One narrower risk survives and is worth fixing. In the schema, only `additions` and `deletions` are **required**; `file`, `patch` and `status` are optional. Our parser throws `FormatException` and fails the entire review if any is absent (`opencode_review_service.dart:88-95`). All six files in the live probe carried all three, but a binary file or an edge case would abort the whole snapshot. The parser is strict where the contract is permissive.

### 2.1 What the server actually offers

Verified routes, with parameters taken from the live spec:

- `GET /session/{sessionID}/diff` — query `messageID?`, returns `SnapshotFileDiff[]`. Session-scoped.
- `GET /vcs/diff` — query **`mode` (required, `git` | `branch`)**, `context?` (integer), returns `VcsFileDiff[]` with the same field shape.
- `GET /vcs/diff/raw` — the unstructured diff.
- `GET /vcs/status` — returns `VcsFileStatus[]` = `{file, additions, deletions, status}`, all required.
- `GET /vcs` — returns `{branch, default_branch}`. The published docs and the dev SDK both claim `{branch}` only.
- `POST /vcs/apply` — body `{patch}`, returns `{applied}`, and fails with `VcsApplyError` whose reason is `non-git` or `not-clean`.

Measured behaviour on this repository, current branch three commits ahead of `main`:

- `mode=git` returned the uncommitted work — 1 file.
- `mode=branch` returned the branch against `default_branch` — 6 files, every one carrying `file`, `patch` and `status`.

**Two of the three requested comparisons are therefore native today**: uncommitted work via `mode=git`, and current branch against the default branch via `mode=branch`. What remains genuinely unavailable is an **arbitrary** comparison — branch A against branch B, or commit against commit — because `mode` is a two-value enum with no ref parameters.

For that remaining case, in order of preference:

1. **Contribute upstream.** The endpoint already exists; it needs two optional ref parameters. That is a far smaller contribution than inventing a route, and every client gains.
2. **`POST /session/:id/shell`** to run `git diff`, under the user's authority in the parent session, never inside a deny-all reviewer child, with the command built from validated ref names and never from model output.

Extension mechanisms were checked and do not help: **custom tools** run server-side but are only callable by a model during a conversation, and **plugins** cannot register an HTTP route. Neither can serve as a client data path.

### 2.2 The `context` parameter changes the economics

`GET /vcs/diff` accepts a `context` integer, and it matters far more than it looks. Measured on the same six files:

| `context` | total patch characters |
| --- | --- |
| default (omitted) | ~237,000 |
| 25 | 64,949 |
| 10 | 56,613 |
| 3 | 51,568 |
| 0 | 48,722 |

Omitting `context` appears to return something close to whole-file content. Our review snapshot is bounded to 20 files and 200,000 patch characters (`ARCHITECTURE.md:83`), so **six files already overflow that budget at the default**, while the same six cost a quarter of it at `context=10`. Much of the snapshot budget is currently spent on unchanged context rather than on changes, which directly limits how much of a change set a review can see.

Two consequences: pass an explicit `context` when building a snapshot, and treat **context expansion as a server capability** rather than a client-side algorithm. Section 3.5 defers expansion as expensive on the assumption that we hold only a fixed patch; that assumption is wrong — the server will widen the window on request.

### 2.3 Mechanisms found that are worth using

- `POST /session/:id/fork` — forks a session at a message. For adversarial review, forking gives a challenger the *same* context as the reviewer it contests, instead of rebuilding it from scratch with `createChild`.
- `GET /session/:id/children` — lists child sessions, so reviewer children can be reattached after an app restart rather than persisted by id alone.
- The `session.diff` event, listed in the plugin event API. A diff that changes announces itself, so finding staleness can be reactive instead of polled. This bears directly on open question 6.

### 2.2 The model to expose

Converged independently from magit's command vocabulary (`magit-diff.el:1461-1526`) and Jujutsu's working-copy-as-commit model (`docs/working-copy.md:9-12`): do not expose three orthogonal axes.

A review target is **one comparison**: `{old: RevisionRef, new: RevisionRef}` where a `RevisionRef` is a branch, a commit, or the current uncommitted state. Uncommitted work is not a special case, it is simply something the `new` side can be. This collapses branch-vs-branch, commit-vs-commit and "my current mess" into a single concept, and it matches the flat file list the server already returns.

Two refinements worth copying:

- **Resolve `..` versus `...` automatically.** magit computes ancestry and only asks the user when the answer is genuinely ambiguous (`magit-diff.el:1422-1443`). Never make the user learn Git range syntax.
- **A context-sensitive default.** magit's `magit-diff-dwim` (`:1305-1355`) picks the right comparison from where the user is. Reviewing from a session should default to that session's diff; reviewing from the workspace should default to uncommitted work.

Explicitly **out of scope**: staging, discarding, and hunk application. magit and lazygit build these on `git apply --cached` (`magit-apply.el:216-243`), which mutates the repository. `ARCHITECTURE.md:85` forbids it and that must not change. We take their *addressing* model — file, hunk, line — and none of their mutation.

---

## 3. The review surface

Ordered by value over cost. Every item names where the idea comes from.

### 3.1 Foundations (no agent changes, shippable immediately)

1. **The diff is the screen.** Remove the outer `ExpansionTile`. Files collapse individually, which `DiffViewer` already does.
2. **Stable, diff-derived line identity.** react-diff-view keys every line as `N<oldLine>` / `I<newLine>` / `D<oldLine>` (`utils/diff/getChangeKey.ts:3-13`) and uses the same key for widgets *and* selection. Replace our counter-based `DiffRow.id` so a line can be addressed from outside the parser. Low cost, and a prerequisite for everything below.
3. **Render hunk boundaries.** We parse `DiffHunk.header` (`diff_model.dart:37`) and never display it, so two hunks run together with no sign of the skipped lines. `delta` treats this as a first-class element. The data exists; only a row is missing.
4. **Collapse generated files by default.** GitLab drives this from `.gitattributes` (`docs.gitlab.com`, 2026-09-02). Config-only, and this repository generates Drift code and carries lockfiles nobody wants to page through.
5. **File tree with a focused single-file pane on narrow widths.** lazygit's panel model (`pkg/gui/filetree/file_tree.go:33-241`) reads better on a phone than magit's one long scroll. On desktop, keep the continuous scroll.

### 3.2 Anchoring and triage

6. **Findings rendered inline, on the line they concern.** react-diff-view inserts a widget as an extra row in the same list (`Hunk/UnifiedHunk/index.tsx:9-24`), which maps exactly onto our sliver list. The domain model already has the coordinates.
7. **One aggregated thread list, filterable by status.** GitHub's Conversations menu (`docs.github.com`, 2026-09-02) is the single highest-leverage primitive found in this entire study: it turns "scroll every file" into "triage a list".
8. **Line and range selection.** Selection must reuse the identity from item 2, as react-diff-view does (`hooks/useChangeSelect.ts:11-31`). This is what lets the developer point at code and start an argument.
9. **No `outdated` machinery.** GitHub stores a `diff_hunk` snapshot per comment and maintains an `isOutdated` flag because the pull request moves under the comments. Our snapshot is frozen by design (`ARCHITECTURE.md:83`), so anchors cannot drift inside a run. This is complexity we simply do not pay.

### 3.3 What to review, and what changed since last time

10. **Per-file, per-revision review state.** Reviewable tracks `(file, revision, reviewer)` and defaults the diff bounds to "everything since you last looked" (`docs.reviewable.io/files`, 2026-09-02). This is the strongest published answer to *what changed since I reviewed this*, and it is the natural fit for agents re-reviewing an evolving diff.
11. **Diff between two revisions of the same target, not only against base.** Gerrit's patch-set pair (`gerrit-review.googlesource.com/Documentation/user-review-ui.html`, 2026-09-02). We get this cheaply because we already persist snapshots (`review_history_store.dart`): diffing snapshot N against snapshot N+1 is a client-side operation.
12. **Suppress rebase noise.** Gerrit subtracts edits attributable to a rebase by diffing the parents, and drops files whose changes are entirely rebase-induced. This matters more with agents than with humans, because agents amend and rewrite constantly.
13. **A cheaper fallback if 10 is too much for a first slice**: GitLab's content-hash-keyed "Viewed" checkbox. It survives a rebase that did not touch the file, but it loses "show me only the delta". Pick one, not both.

### 3.4 Collaboration between the developer and the agents

14. **Resolution kind, not a boolean.** Gerrit distinguishes "Done" from "Ack" — fixed versus acknowledged-but-unchanged. Store `fixed | acknowledged | wont_fix` so an agent knows not to re-raise something the developer deliberately overrode.
15. **Per-participant standing on a thread.** Reviewable gives each participant a disposition (`docs.reviewable.io/discussions`, 2026-09-02). A useful subset for us is three values: `blocking`, `working`, `satisfied`. An agent can mark itself `working` on its own finding while the developer is still `blocking` on another point in the same thread, without one global resolve flattening both.
16. **Whose turn is it.** Gerrit's attention set, with its rule that **service accounts are excluded**. Transposed: reviewer-role entities take turns, signal-producing agents never claim one. Without this, N agents make the queue meaningless for one developer.
17. **Per-hunk accept/reject, plus a coarse rollback.** Zed's agent panel offers hunk-level accept/reject over a multi-buffer review, with checkpoint restore as the blunt instrument (`zed.dev/docs/ai/agent-panel`, 2026-09-02). Graduated control beats a single binary.
18. **Summary-only agent boundary.** Claude Code's subagents return a summary, never their raw exploration (`code.claude.com/docs/en/sub-agents`, 2026-09-02). A reviewer's greps and dead ends must never enter the shared debate transcript.
19. **Steer versus queue.** Cursor distinguishes interrupting an agent at its next tool call from appending a note for later (`cursor.com/docs/agent/overview`, 2026-09-02). A debate UI needs both, explicitly.
20. **Batched suggestions applied as one commit.** GitLab batches suggestions across files into a single commit with `Co-authored-by` trailers. Naming the *agent* in the trailer keeps provenance in Git history at no cost. Note this is the one place where review would stop being read-only, so it needs an explicit decision.

### 3.5 Deliberately deferred

- **Side-by-side view.** react-diff-view treats it as a swappable renderer over the same hunk data, so it can be added later without disturbing the model. Needs a row-pairing algorithm we do not have.
- **Word-level intra-line diff.** `delta` implements real token alignment (`edits.rs:24`); our highlighter only does syntax. Heavy, and orthogonal.
- **Context expansion.** **No longer deferred.** `GET /vcs/diff` takes a `context` parameter and the server widens the window itself (section 2.2), so this needs neither a splice algorithm nor a second data source — only a refetch and a re-parse. Promote it into the delivery slices.
- **Word-level intra-line diff.** Still deferred. `delta` implements real token alignment (`edits.rs:24`); our highlighter only does syntax. The pairing algorithm remains the cost, and nothing on the server helps here.
- **Structural diff.** difftastic degrades safely — byte limit 1 MB, graph limit 3M nodes, parse-error fallback to line diff (`src/options.rs:17-21`, `src/main.rs:700-725`) — but it is a native binary with tree-sitter grammars. Web has no Native Assets, so it can only ever run server-side, and its own documentation admits cases where the structural diff is *more* confusing than a line diff (`manual/src/tricky_cases.md:305-325`). Optional server-side mode at best, never a default, never a client dependency.
- **Dependent change chains.** Gerrit's relation chain matters for stacked reviews. Out of scope until stacking exists.

---

## 4. Anti-patterns, with reasons

Drawn from what the AI review products actually ship.

- **Reaction-driven suppression as the only noise control** (Sourcery). It teaches the model to stop mentioning a category, not to reconsider whether a claim was true. It optimises for silence, not correctness.
- **Acceptance rate and downvote rate as the headline quality metric** (Graphite). A suggestion is accepted when it is plausible and cheap to apply, not when it is correct. Engagement metric, not precision.
- **Teaching that silently rewrites future behaviour while leaving the disputed finding untouched** (CodeRabbit Learnings). The finding and its resolution must live in the same record.
- **Blocking a merge on an unconfirmed finding.** Cursor BugBot's check defaults to `neutral` precisely to avoid this. A hypothesis must never gate anything by default.
- **Confident prose in place of evidence.** Ellipsis promises to file a finding only when it can point at the line and name the input that breaks it — but that confirmation is still the model's own judgement, not an external oracle. Our advantage is to make the oracle real and re-runnable.
- **Trigger comments embedded in source files** (Aider). Elegant for pair programming, wrong here: the review scope must be an immutable snapshot, not mutable source the agent could also edit.

---

## 5. Where the differentiation actually is

Confirmed by absence across CodeRabbit, Greptile, Graphite Diamond, Cursor BugBot, Sourcery and Ellipsis:

- None exposes **disagreement as a browsable object**. Every reply mechanism either silently changes future behaviour or closes the thread. None shows one agent contesting another's claim with a counter-argument the developer can read and rule on.
- None ties a finding's confirmed state to an **executable oracle the user can re-run**.
- None separates **the agent that proposes** from **the agent that verifies** as distinct, provenance-tracked identities.
- None measures whether **reviewer N+1 changed the outcome**.

Qodo's own 2025 survey (n=609) reports that when an AI review tool is enabled, 80% of pull requests receive no human comment at all. They present it as a productivity win. Read against our thesis it is a rubber-stamping alarm: a review layer that removes the human from four PRs in five is the opposite of what we are building.

---

## 5.1 Measure against published baselines, not invented metrics

Three 2026 artefacts remove any excuse for inventing our own evaluation.

- **CR-Bench and CR-Evaluator** (`arXiv:2603.11078`, 2026-03-10) is a fine-grained benchmark built for the case where false positives are expensive, and it exposes a resolution-rate versus spurious-findings frontier. Adopt or reproduce it rather than defining fresh precision metrics.
- **Archer** (`arXiv:2607.01808`, 2026-07-02) is a field study on LLVM review gating findings behind executable evidence, and found 21% of open and 11% of closed pull requests buggy on a mature project. It validates the evidence-first ordering at production scale in another domain.
- **A mined study of 31k CodeRabbit review and feedback pairs across 239 repositories** (`arXiv:2607.03316v2`, 2026-07-23) reports a **56.3% rejection rate**, dominated by false positives, out-of-scope remarks and misalignment. That is the number to beat, and it means adding layers on top of already-noisy first passes compounds a measured problem rather than a hypothetical one.

One more result belongs here because it disciplines the whole ambition: across 1.02M pull requests in 207 repositories, agent involvement sped up review decisions but the efficiency gains **did not translate into better review quality** (`arXiv:2607.13196`, 2026-07-14). More machinery is not self-justifying.

## 6. Delivery slices

Each slice is independently reviewable and shippable.

1. **Diff-first layout.** Items 1, 3, 4, 5. No agent changes, no schema changes.
2. **Addressable lines.** Item 2. Parser-only, prerequisite for everything after.
3. **Inline findings and the triage list.** Items 6, 7. Uses the existing domain model unchanged.
4. **Selection.** Item 8.
5. **Arbitrary diff sources.** Section 2, gated on the `GET /vcs` probe and the upstream-versus-shell decision. Uncommitted work can ship before branch and commit comparison, since it needs no new server capability.
6. **Threads and conversation.** Items 14, 15, 16, 18, 19. Requires a new repository method, new entities, a schema increment, and keeping reviewer child sessions alive. Child sessions are ordinary sessions, and `abort` stops a generation rather than destroying the session, so no new session plumbing is needed.
7. **Adversarial verdicts.** Promote `ReviewFindingStatus` from its single value to a real lifecycle, wired to the debate protocol already specified in `agentic-code-review-sota.md`.
8. **Revision awareness.** Items 10, 11, 12, 13.

---

## 7. Open questions

These change the shape of the schema and must be answered before implementation, not guessed.

0. **Closed.** The contract is sound; the hypothesis was refuted against the live server. Two smaller items replace it, both real: make the diff parser tolerant of the optional `file`, `patch` and `status` fields instead of failing the whole snapshot, and pass an explicit `context` so the snapshot budget is spent on changes rather than on unchanged context.
1. **How do we get branch and commit diffs?** Mostly answered by `GET /vcs/diff`: uncommitted work and current-branch-against-default are native today. Only an **arbitrary** ref-to-ref comparison is missing, and the decision is narrow — contribute two optional ref parameters to an endpoint that already exists, or shell out under the user's authority in the meantime.
2. **Diff bounds: one cursor per review, or one per file?** My reversibility argument does not survive contact with the evidence. **No surveyed tool has ever migrated from per-change to per-file bounds.** Gerrit has had fifteen years and never added a per-file notion; its `copyCondition` predicates are strictly change-level, and `has:unchanged-files` compares the whole file list rather than tracking a file (Gerrit 3.14.2 config reference, 2026-09-02). GitHub and GitLab both stayed at a coarse per-file boolean. Reviewable built per-file bounds from day one and documents the resulting footguns: marking a file reviewed against non-default bounds is "not advised" because unreviewed changes stay hidden, long reviews need a **lossy** "Compact revisions" operation that can reassign discussions to the wrong revision, and per-reviewer bounds break next/previous navigation for everyone but the first reviewer (`docs.reviewable.io/files`, Reviewable issue #404, both 2026-09-02).

   The useful discovery is that **GitHub runs two granularities at once**, and they were invented separately: a coarse per-file "Viewed" boolean that resets on any change to the file, plus fine per-comment outdating anchored to the comment's own hunk. Revised recommendation: copy that pairing rather than choosing between Gerrit and Reviewable. A coarse per-file viewed flag costs one column; per-finding staleness is question 6 and is needed regardless. If per-file *bounds* are ever wanted, budget a real transition rather than assuming a free additive migration.
3. **Do we copy GitHub's pending-review batching?** **My earlier recommendation was wrong.** I claimed batching exists only to spare a team from notifications. Gerrit, GitLab and GitHub all document a different primary rationale: drafts let a reviewer revise before publishing, and one atomic submission ties the individual findings to a single verdict, so comment 1 is never published before comment 4 contradicts it (`gerrit-review.googlesource.com/Documentation/user-review-ui.html`, `docs.gitlab.com/user/discussions/`, both 2026-09-02). Three independent tools converging on the same shape is not a notification optimisation. Cursor BugBot does the same, posting one consolidated report per run rather than streaming findings (`cursor.com/docs/bugbot`, 2026-09-02). None of this is team-size dependent.

   We already batch at the pass level (`ARCHITECTURE.md:85`). The real question is **cross-pass** batching: hold correctness, security and tests until the whole set completes, or surface each as it finishes. Revised recommendation: **hold**, because a fast security pass reporting all-clear before a slower correctness pass contradicts it is precisely the incoherence the draft/publish model exists to prevent.
4. **Who breaks a tie in the debate?** Recommendation held — no arbitrating model — and the 2026 evidence strengthened it. Judge reliability got *worse* on inspection: judges are near chance at detecting omissions, AUC .50–.63 versus .79–.94 for added or altered content (`arXiv:2608.31016`, 2026-08-31), which is exactly the shape of a missing-check defect. Rank reversal depends on prompt language in 7 of 15 backbone pairs (`arXiv:2608.22432`, 2026-08-23). Judge severity drifts across versions of the same model (`arXiv:2608.29517`, 2026-08-30). Multi-agent debate results remain net negative: accuracy decreases over rounds as models favour agreement over challenging flawed reasoning (`arXiv:2509.05396v2`), and sycophancy drives premature consensus collapse (`arXiv:2509.23055`).

   **Nobody has measured escalate-to-human against a third-model adjudicator directly.** Honest gap. But `JuryProbe` (TMLR, 2026-08) offers a better third option than either of mine: reference-free judge panels share correlated false negatives, with false-consensus lift of 3–18×, and **routing to external grounding eliminates unanimous false consensus** where adding opinion-holders does not. Revised recommendation: on disagreement, **route to another external oracle first** — a test, an analyzer, a reproduction — and fall back to bare `unresolved` only when no further oracle evidence is obtainable. This pulls the lever `agentic-code-review-sota.md` already identifies rather than adding a judge.

   One condition against my own framing: expert reviewers resist automation bias better than lay users (`arXiv:2512.12500`, 623 lay and 153 physicians). So "an arbitrator manufactures false confidence" is proven for novices, not for the expert profile this product targets. Treat human resilience as something to measure, not assume.
5. **Does applying a suggestion stay out of scope?** Recommendation held, but the reasoning was weak and is now sharper. The real argument is not that `ARCHITECTURE.md:85` says so; it is that the deny-all, tool-free child construction (`:83`) is a **structural** guarantee, whereas the chat flow's write path depends on a per-action permission dialog (`:300`) that a user can rubber-stamp under review fatigue — the exact state a multi-pass review produces. Every external tool surveyed gates writes on a human's repository access, never on the reviewer's own privilege.

   The strongest case against, which deserves recording: the chat flow already writes with the same models and the same untrusted-diff exposure, so the wall may protect nothing while forcing the developer to retype a fix in a second session — itself an error-injection step. Revised framing: **C is a scope boundary of this PoC, not a permanent law.** If an apply action is ever added, the guardrail moves to that action's authorisation path: explicit human trigger, separately reviewable commit, and no silent delivery when verification fails — CodeRabbit's Autofix documents delivering changes even when its own verification step fails, which is the failure mode to avoid.

   A separate lever this surfaced: self-enhancement bias (Zheng et al., NeurIPS 2023) argues the *fix* should be generated by a different model than the one that found the defect, independently of who holds write access. No 2026 successor paper on agentic self-verification for code review was found.
6. **When does a finding go stale?** Recommendation held for a finding that behaves like a review comment: GitHub's outdating is anchored to the comment's own position and hunk, and its REST documentation warns that a comment is rendered outdated when "a subsequent commit modifies the line you specify" (`docs.github.com/en/rest/pulls/comments`, 2026-09-02). If instead a finding behaves like a file-level mark, both GitHub and GitLab invalidate on **any** byte change to the file, so choosing otherwise is a deliberate departure worth naming.

   Two things I had missed. First, Gerrit offers a **third model**: it never stales a comment at all, it re-anchors unresolved comments onto the latest patch set. Re-anchoring may be better than invalidating, because a finding that is still true should not disappear because a line moved. Second, no tool publishes its exact matching rule — GitHub's stops at "outdated by newer changes" — so we must define our own predicate explicitly: is a finding stale when its lines no longer resolve in the new diff, when their content is edited, or when their containing hunk is touched? That choice must be written down before the schema is fixed.

   The `session.diff` event gives us the trigger for free either way.
