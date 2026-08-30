# Agentic Code Review for Prompt

State-of-the-art research and product proposal, current through August 29, 2026.

This document is a research report, not a binding architecture decision. It records the evidence, product proposal, risks, package strategy, evaluation plan, and delivery sequence for a future agent-assisted code-review subsystem in Prompt. Any implementation still requires explicit architecture decisions in `ARCHITECTURE.md` and product scope in `PLAN.md`.

## Executive Summary

Code production is becoming cheaper and faster while human review and integration capacity is not scaling at the same rate. The resulting bottleneck is no longer primarily writing a feature; it is establishing enough evidence to safely accept, integrate, and own changes that humans may not understand in detail.

A contingent of reviewing models is promising, but the product must not become a majority vote among language models. Different models may share training data, architecture patterns, benchmark contamination, contextual errors, and incentives. Agreement between agents is not evidence, and provider diversity is only a proxy for independence.

The recommended product is an **evidence-driven, multi-model adversarial review council** with:

- genuinely independent first passes;
- different providers, models, roles, prompts, contexts, tools, and oracles;
- structured and precisely anchored findings;
- visible disagreement and bounded counterargument;
- tests, static analysis, and other external oracles;
- explicit human decisions;
- complete provenance and audit records;
- measurements that establish whether each additional reviewer reduces risk or human review time.

The differentiator is not merely that several agents review a pull request. Claude Code Review, Qodo, CodeRabbit, Greptile, and other products already advertise specialized or parallel review agents. Prompt becomes meaningfully different only if it makes individual opinions and disagreements visible, requires executable evidence, supports heterogeneous providers under user control, preserves privacy, and measures the marginal value of diversity.

Possible product names are **Contingent Review**, **Review Council**, or **Adversarial Review Council**. In French, *revue contradictoire* communicates the intended process more accurately than a simple adversarial contest.

## Production State of the Art

| Product | Relevant practices | Important qualification |
| --- | --- | --- |
| [GitHub Copilot Code Review](https://docs.github.com/en/copilot/concepts/agents/code-review) | Repository context, incremental review, inline comments, contextual instructions, skills, MCP integrations, and fix suggestions | The review does not constitute human approval and the reviewer model is not freely selectable |
| [Claude Code Review](https://code.claude.com/docs/en/code-review) | Specialized agents, parallel candidate generation, verification, deduplication, ranking, inline comments, and incremental review | Documented as a research preview with material per-review cost and availability constraints |
| [OpenAI Codex Code Review](https://developers.openai.com/codex/cloud/code-review.md) | GitHub-triggered review, `AGENTS.md` guidance, focus on high-severity P0/P1 findings, and a separate security review workflow | No documented transparent multi-provider debate or user-selected review ensemble |
| [Gemini Code Assist for GitHub](https://docs.cloud.google.com/gemini/docs/code-review/review-repo-code) | Pull-request summaries, repository and pull-request context, and interaction from review comments | Some Enterprise capabilities remain in Preview |
| [Cursor Bugbot](https://cursor.com/docs/bugbot) | Incremental reviews, persistent findings, repository rules, dry-run APIs, cost visibility, and resolution analytics | Primarily a reviewer integrated into the Cursor product and workflow |
| [Amazon Q Developer](https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/code-reviews.html) | Generative review combined with CodeGuru rules, SAST, secrets, infrastructure-as-code checks, deployment risk, and dependency analysis | Strongly integrated with the AWS ecosystem and subject to documented size and language limits |
| [CodeRabbit](https://docs.coderabbit.ai/guides/code-review-overview) | Repository context, incremental review, code graph, chat, linters, scanners, and one-click suggestions | Public precision and recall numbers are predominantly vendor claims rather than independent comparisons |
| [Qodo](https://docs.qodo.ai/code-review/overview) and [PR-Agent](https://github.com/The-PR-Agent/pr-agent) | Specialized review agents, requirements context, history-aware review, deduplication, persistent comments, and multi-provider routing | Commercial quality claims are not a shared independent benchmark; PR-Agent and Qodo have different product and governance paths |
| [Greptile](https://www.greptile.com/) | Repository graph, out-of-diff context, swarm review, history-based learning, and test-generation sandbox concepts | Most public quality evidence remains vendor-selected examples and testimonials |
| [Graphite](https://graphite.dev/features) | AI review integrated with stacked changes, pull-request inboxes, CI, and merge queues | Public technical details about models, validation, and measured accuracy are limited |
| [Snyk Code](https://snyk.io/product/snyk-code/) | Security-focused data-flow analysis, vulnerability knowledge, pull-request integration, and assisted fixes | More specialized for application security than general design or behavioral review; performance figures are vendor claims |
| [Semgrep Code](https://semgrep.dev/docs/semgrep-code/overview) | Inspectable rules, custom policies, inter-file analysis, CI checks, triage, and AI-assisted logic analysis | Coverage remains bounded by rules, languages, configuration, and the privacy boundary of managed AI scans |
| [GitHub CodeQL](https://docs.github.com/en/code-security/code-scanning/introduction-to-code-scanning/about-code-scanning-with-codeql) | Versioned queries over a code database, interprocedural analysis for supported languages, CI checks, and explainable paths | It is a powerful deterministic oracle for covered properties, not a complete semantic code reviewer |

The mature production pattern is:

```text
Immutable diff and requirements
→ repository-wide context and change history
→ deterministic tests, linters, SAST, SCA, and policy checks
→ specialized review agents
→ candidate verification and behavioral reproduction
→ correlation, deduplication, and risk ranking
→ inline findings and a stable machine-readable check
→ incremental re-review after new commits
→ explicit human decision
```

Sending a diff to one unconstrained prompt is no longer state of the art.

### Repository Context Beyond the Diff

Advanced reviewers combine the changed lines with symbols, call relationships, repository rules, historical decisions, requirements, issue context, prior pull requests, and threat models. This improves recall but also expands the prompt-injection and confidentiality surface. Context collection must therefore be explicit, attributable, bounded, and policy-controlled.

### Incremental Review

Incrementality is an operational requirement. A new commit should re-evaluate affected findings, retain unresolved findings, mark invalid anchors stale, and avoid re-posting unchanged comments. This reduces cost and reviewer fatigue while preserving finding identity across revisions.

### Findings as Durable Entities

A production finding needs a precise file and line anchor, category, severity, expected behavior, observed or hypothesized behavior, evidence, provenance, proposed verification, lifecycle status, and relationship to prior findings. A stream of prose comments is insufficient for reliable integration.

### Human Approval Remains Separate

Responsible products keep AI findings, deterministic checks, human approval, and merge gating distinct. Prompt should never convert an agent consensus directly into approval, commit application, or merge authorization.

### Review Memory Must Be Traceable

Repository memory is useful only when every remembered rule or decision cites a source, identifies the repository and revision scope, can be corrected or deleted, and expires or becomes stale when its evidence disappears. Learned preferences must never silently become permanent security policy.

## Scientific Evidence for Multi-Agent Review

The research supports hypothesis diversity and structured criticism, but it does not establish that multi-model debate improves real-world code-review precision.

| Technique | Evidence | Limitation for code review |
| --- | --- | --- |
| [Self-consistency](https://arxiv.org/abs/2203.11171), ICLR 2023 | Multiple reasoning samples improve several general reasoning benchmarks | Samples from one model remain correlated and majority vote cannot correct a systematic error |
| [Self-Refine](https://arxiv.org/abs/2303.17651) | Iterative critique and revision improve outputs on several tasks | The same model generates, criticizes, and revises without an external oracle |
| [Multi-agent debate](https://arxiv.org/abs/2305.14325) | Debate improves some mathematical, strategic, and factual benchmarks | It is a preprint about general tasks, not industrial code review or vulnerability verification |
| [AI safety via debate](https://arxiv.org/abs/1805.00899) | Theoretical argument and a constrained MNIST experiment support adversarial challenge | It does not validate large-scale software-review adjudication |
| [Process supervision](https://arxiv.org/abs/2305.20050) | Step-level supervision outperforms outcome-only supervision on MATH | It supports requiring intermediate evidence, not trusting an LLM adjudicator as proof |
| [LLM-as-a-Judge](https://arxiv.org/abs/2306.05685), NeurIPS 2023 | LLM judges can correlate with human preferences | Position, verbosity, self-preference, and reasoning biases limit their use as truth oracles |
| [Mixture-of-Agents](https://arxiv.org/abs/2406.04692) | Layered model aggregation improves several general preference benchmarks | It is a preprint, exposes later agents to earlier answers, and does not measure code-review reliability |
| [Intrinsic self-correction limits](https://arxiv.org/abs/2310.01798), ICLR 2024 | Self-correction without external feedback can fail or degrade reasoning | Every correction needs a test, trace, specification, or other external signal |
| [Sycophancy](https://arxiv.org/abs/2310.13548) | Assistants may prefer agreement or persuasive answers over truth | Reviewers and judges can converge socially without becoming more correct |

The defensible conclusion is:

> Multi-agent review may improve the diversity of hypotheses, but only external evidence can convert a hypothesis into a confirmed finding.

## Recommended Review Protocol

### 1. Establish an Immutable Snapshot

Every review is bound to a repository identity, base SHA, head SHA, commit range, exact diff, requirements snapshot, review-policy version, and reviewer configuration. A changed head SHA makes affected findings stale until they are revalidated.

### 2. Run Independent First Passes

Initial reviewers do not see each other's conclusions. Useful roles include correctness and regression, security and trust boundaries, tests and contracts, architecture and maintainability, performance and concurrency, dependencies and supply chain, migration compatibility, and an explicit challenger tasked with finding counterexamples.

Real diversity should vary more than provider names. The system should vary model, prompt, role, context selection, available tools, and oracle. Five samples of the same model with the same prompt and context are not five independent reviewers.

### 3. Require Structured Findings

Each finding records:

- file, line range, side of the diff, and revision;
- category and severity;
- expected behavior or violated requirement;
- observed behavior or hypothesis;
- trigger preconditions and reachability;
- a concrete reproduction scenario;
- impact;
- evidence and citations;
- the expected test or command;
- provider, model, version, role, prompt-template hash, and tool configuration;
- confidence as an uncalibrated estimate unless calibration evidence exists;
- an explicit abstention option.

Recommended finding states are:

```text
hypothesis
confirmed
refuted
unknown
duplicate
accepted-risk
fixed
stale
```

A finding without executable or normative evidence cannot become `confirmed`.

### 4. Run External Oracles Before Debate

Depending on the change, collect compilation and type results, targeted tests, static analysis, CodeQL or Semgrep findings, dependency and lockfile analysis, secret scans, mutation tests, fuzzing or property-based tests, schema and migration checks, and bounded sandbox reproductions.

A test that fails for the expected reason and passes after the correction is stronger evidence than unanimous model agreement.

### 5. Correlate Without Destroying Evidence

Similar findings may be grouped, but every original opinion remains available. The system records which reviewers detected, missed, supported, or rejected the issue; which evidence they used; and how their position changed. Deduplication must not erase the only correct observation.

### 6. Conduct Bounded Adversarial Debate

Debate begins only after independent first passes. For each contested finding, one reviewer states the hypothesis, a challenger must refute a precondition or provide a counterexample, the first reviewer responds to that specific challenge, and an evidence worker attempts to produce an external oracle. Debate is bounded by turns, time, tokens, and cost.

The system should not ask only which reviewer is right. It should ask which property is allegedly violated, whether the path is reachable, which input triggers it, which test distinguishes the positions, and which missing evidence prevents a conclusion.

### 7. Adjudicate Without Treating the Judge as an Oracle

The adjudicator receives normalized findings, evidence, and objections rather than uncontrolled complete conversations. Its available outcomes are `confirmed`, `refuted`, `hypothesis`, `undetermined`, and `out-of-scope`. Its verdict remains another opinion until it is connected to an observable oracle.

To reduce judge bias, provider identities should be hidden when possible, argument order should be randomized, important pairwise evaluations should be repeated with reversed positions, majority vote must not imply truth, and calibration should be measured against known cases.

### 8. Preserve Explicit Human Authority

The human reviewer can accept or dismiss a finding, request evidence, request another reviewer, open a targeted debate, record an accepted risk, ask for a regression test, delegate a fix in a separate context, and inspect the patch before application. The MVP must not approve, apply, commit, or merge changes automatically.

## Proposed User Experience

### Main Review Layout

```text
┌─────────────────┬──────────────────────────────┬────────────────────────┐
│ Files / Commits │ Unified or split diff        │ Review Council         │
│ Findings        │ Inline threads and selection │ Opinions and evidence  │
│ Checks          │ Precise revision anchors     │ Debate and decision    │
└─────────────────┴──────────────────────────────┴────────────────────────┘
```

### Primary Views

- **Overview** shows risk, required checks, reviewers, progress, cost, and latency.
- **Changes** provides a GitHub-like unified or split diff with virtualized files and inline threads.
- **Commits** explains the review range and supports review by individual commit.
- **Findings** filters by severity, category, reviewer, verification state, and revision.
- **Council** preserves each independent stance instead of displaying only an aggregate answer.
- **Debate** shows objections, counterexamples, changed positions, and the adjudication result.
- **Evidence** contains test runs, traces, analyzers, dependency checks, and normative citations.
- **Provenance** shows snapshots, provider and model versions, prompts, tools, permissions, and timestamps.
- **Decision** records accepted findings, dismissed hypotheses, accepted risks, required changes, and human sign-off.

### Line-Level Actions

For a selected line or range, the user can ask for an explanation, request a named reviewer, search for a counterexample, compare the change with architecture rules, request a security analysis, request a red regression test, open a bounded debate, or propose a patch without applying it.

### Progressive Results and Partial Failure

Review status should remain visible while agents and tools run:

```text
Correctness reviewer     completed
Security reviewer        running
Test reviewer            completed
DeepSeek challenger      failed
Static checks            7/8 passed
Adjudication             waiting
```

One provider failure must not erase other results. Partial, interrupted, cancelled, unknown, and stale states remain explicit.

## Prompt and OpenCode Architecture

OpenCode currently documents server primitives for sessions with optional `parentID`, session children, explicit `{providerID, modelID}` message selection, configurable agents, synchronous messages, `prompt_async`, abort, global SSE events, diffs, files, search, and permissions with `allow`, `ask`, and `deny`. See [OpenCode Server](https://opencode.ai/docs/server/), [Agents](https://opencode.ai/docs/agents/), and [Permissions](https://opencode.ai/docs/permissions/).

OpenCode does not document a native operation that runs an N-model debate, review ensemble, or adjudication workflow. Prompt must implement that orchestration at the application layer. Creating a session with `parentID` records a relationship; it does not automatically execute a reviewer. Prompt must send the task, follow its events, reconcile completion, and handle failure explicitly.

```text
ReviewRepository
  └── ReviewOrchestrator
        ├── SnapshotService
        ├── ReviewerSession[1..N]
        ├── OracleRunner
        ├── FindingCorrelator
        ├── DebateCoordinator
        ├── AdjudicationService
        └── ReviewLocalStore
```

The repository remains the source of truth for review state. OpenCode services know REST, SSE, sessions, providers, models, agents, and permissions, but not widgets or adjudication rules. View models expose typed states and commands and do not call OpenCode directly.

### Capability Negotiation

The connected server's OpenAPI 3.1 document at `/doc` should be the operational source of truth. Prompt must negotiate capabilities by server version and schema instead of assuming that public documentation matches every connected server. Experimental endpoints remain isolated behind capability facades.

### Queueing, Cancellation, and Recovery

The review subsystem should reuse Prompt's durable asynchronous principles: one demultiplexed event stream per profile, bounded reviewer concurrency, explicit cancellation followed by OpenCode abort, REST reconciliation after reconnect, durable run state, no silent promotion of a partial run to completed, and no cancellation of an active review merely because another review was requested.

### Permissions

Read-only behavior cannot be guaranteed by hiding editing controls in the client. OpenCode permissions are enforced by server and agent configuration. Prompt must inspect or attest the effective review-agent policy before execution and reject a reviewer whose tools or inherited permissions exceed the selected policy.

## Domain Model

Core entities are:

```text
ReviewTarget
ReviewSnapshot
ReviewRun
ReviewerConfiguration
ReviewerPass
ReviewFile
ReviewLineAnchor
ReviewThread
ReviewFinding
ReviewEvidence
ReviewerStance
ReviewDisagreement
ReviewDebate
ReviewAdjudication
ReviewOracleResult
ReviewDecision
ReviewPatchProposal
ReviewAuditEntry
```

The recommended run lifecycle is:

```text
draft
→ snapshotting
→ queued
→ independent-review
→ evidence-collection
→ correlation
→ debate
→ adjudication
→ awaiting-human
→ accepted | needs-changes | dismissed
```

Failure and invalidation states remain separate:

```text
partial
cancelled
failed
unknown
stale
```

Every finding is tied to an immutable snapshot, reviewer provenance, a line anchor that can become stale, and at least one evidence item or an explicit `unsubstantiated` marker.

## Security Model

### Treat the Repository as Hostile Input

Code, comments, documentation, `AGENTS.md`, issues, pull-request descriptions, tool output, commit messages, fixtures, configuration files, dependency metadata, and other reviewer answers are untrusted data. An instruction found in repository content never automatically becomes a system instruction.

### Isolation and Least Privilege

- Reviewers are read-only by default.
- No credentials, authorization headers, prompts, private paths, or user content are logged.
- Filesystem access is bounded to an immutable snapshot.
- Network access is denied by default and granted per reviewed capability.
- Commands and tools use explicit allowlists.
- CPU, memory, runtime, output, token, and cost budgets are enforced.
- Each reviewer receives an isolated session and context.
- Reviewers do not share mutable worktrees, databases, ports, build directories, or devices.
- The fixer is separated from the reviewers and adjudicator.
- No source or test mutation occurs during the evidence-establishment phase.

### Multi-Provider Confidentiality

The user must know which provider receives which files, where processing occurs, whether content is retained, which exclusions are active, whether a local model is actually local, and whether any MCP server or external tool receives repository data.

An example policy is:

```text
public files        → any approved provider
private source      → selected cloud providers only
sensitive source    → local models only
secrets/config      → never sent
```

Redaction, generated-file exclusion, retention, deletion, and export are explicit and auditable. Browser storage remains weaker and persistent review content on Web stays opt-in.

### Supply-Chain Controls

Changes intended for integration should use lockfiles, dependency review, SPDX or CycloneDX SBOMs, CodeQL or Semgrep, secret scanning, pinned CI actions, protected branches, mandatory checks, human sign-off, [SLSA 1.2](https://slsa.dev/spec/v1.2/) provenance, and [Sigstore](https://docs.sigstore.dev/) artifact signatures where appropriate.

## Package and Workspace Strategy

### Immediate Recommendation

Do not migrate the whole Prompt repository to Melos before the review domain is stable. Melos provides script orchestration, selective execution, versioning, and publishing support; it does not discover or enforce the correct architectural boundaries.

[Dart Pub Workspaces](https://dart.dev/tools/pub/workspaces) already provides shared dependency resolution. Melos becomes valuable when multiple packages actually have independent tests, consumers, ownership, or release workflows.

### Initial Feature Boundary

The first implementation can remain an isolated, package-ready feature:

```text
lib/features/review/
  review.dart
  domain/
  data/
  presentation/
```

The `review.dart` facade exports only stable public contracts. No other feature imports review internals. The domain avoids Flutter, HTTP, Drift, platform APIs, package-specific model types, and `BuildContext`.

### Extraction After the Domain Is Proven

```text
packages/
  review_domain/        # Pure Dart entities and invariants
  review_application/   # Pure Dart orchestration and policies
  review_opencode/      # Pure Dart REST/SSE adapter contracts
  review_flutter/       # Flutter view models, screens, and widgets
```

At that point, adopt a native Dart workspace and add Melos only if its change-aware scripts, package filters, versioning, or publishing workflows solve a measured problem.

### Melos Adoption Criteria

- At least three stable packages exist.
- Packages have meaningful independent test matrices.
- CI needs change-aware selective execution.
- More than one application or tool consumes the packages.
- Package ownership or release cadence differs.
- Versioning or publication is needed.

If the review subsystem is already an irreversible strategic commitment, `review_domain` may begin as a pure-Dart package immediately. Moving the entire current application under `apps/prompt/` is not required for that first package and should not be coupled to the review MVP.

## Delivery Roadmap

### Phase 0 — Evaluation and Decisions

- Define the threat model.
- Build a corpus of historical pull requests, known defects, clean negative cases, and injected mutations.
- Define precision, recall, latency, cost, and human-time metrics.
- Decide snapshot identity, permissions, storage, retention, and OpenCode compatibility.
- Establish mono-model and deterministic baselines before building the ensemble.

### Phase 1 — Review Experience Without Agents

- GitHub-like diff browsing.
- Commit, file, and line navigation.
- Local review threads.
- Immutable snapshots.
- Keyboard, mouse, touch, and screen-reader support.
- Lazy and paginated rendering for large diffs.

### Phase 2 — Single-Model Reviewer

- Dedicated OpenCode review session.
- Strict structured output validation.
- Persistent findings and provenance.
- Cancellation, reconnect, reconciliation, and incremental re-review.
- Explicit invalid, partial, and stale states.

### Phase 3 — Deterministic Evidence

- Targeted tests, analysis, and compilation.
- CodeQL or Semgrep adapters.
- Dependency and lockfile review.
- Secret scanning.
- Evidence attached to findings.

### Phase 4 — Independent Review Contingent

- N independent sessions and heterogeneous models.
- Specialized reviewer roles.
- Bounded concurrency and cost budgets.
- Partial-provider failure handling.
- Preserved individual stances.

### Phase 5 — Correlation and Debate

- Finding correlation and non-destructive deduplication.
- Explicit challengers.
- Bounded debate.
- Blinded and order-randomized adjudication.
- Visible disagreement and changed positions.

### Phase 6 — Controlled Remediation

- Generate or request a red regression test.
- Delegate the correction to a separate worker and worktree.
- Present the patch before application.
- Run the same test green without weakening it.
- Perform an independent targeted re-review.
- Never apply or commit silently.

### Phase 7 — Remote Forge Integration

- Import GitHub or GitLab pull requests.
- Publish comments and checks only after explicit authorization.
- Integrate protected branches and merge queues.
- Export provenance and audit records.
- Keep remote mutation separate from local review state.

## Evaluation and Metrics

Success is not the number of comments generated. The system should measure:

- precision of human-accepted findings;
- recall on known defects;
- false-positive rate by severity;
- abstention rate;
- proportion of findings confirmed by executable evidence;
- duplicate rate;
- human review time;
- time to first useful finding;
- cost and latency per reviewer and per accepted finding;
- confidence calibration using Brier score, expected calibration error, or reliability curves;
- reopening rate after a proposed fix;
- regressions introduced by generated fixes;
- correlation between reviewers;
- unanimous false negatives and other false consensus;
- prompt-injection success rate;
- test weakening or bypass attempts;
- marginal value of the Nth reviewer.

The key experiment compares:

```text
one model, one pass
vs one model, N samples
vs N models from one provider
vs N heterogeneous providers
vs N reviewers plus deterministic oracles
```

Without this comparison, Prompt cannot know whether provider diversity improves review or merely increases cost and persuasive output.

## Anti-Patterns to Prohibit

- Majority vote among agents.
- Confidence scores presented as calibrated probabilities without calibration evidence.
- Debate before independent analysis.
- The same agent generating the code, test, fix, and final verdict.
- Consensus automatically becoming approval or a merge gate.
- Silent weakening, deletion, or bypass of tests.
- Treating repository text as system instructions.
- Review agents holding write credentials.
- Automatic merge in the initial product.
- Security claims without reachability, preconditions, and impact.
- Unlimited retention of private code by every provider.
- Deduplication that discards dissenting evidence.
- Introducing Melos only to rearrange directories.

## Architecture Decisions Required Before Implementation

1. Internal feature versus initial pure-Dart package.
2. Snapshot identity and invalidation.
3. Structured finding and evidence schemas.
4. OpenCode session orchestration and capability negotiation.
5. Effective read-only permission attestation.
6. Multi-provider privacy and routing policy.
7. Provenance and audit format.
8. Retention, encryption, and Web persistence.
9. Correlation and non-destructive deduplication.
10. Debate bounds and adjudication semantics.
11. Reviewer, verifier, fixer, and integrator separation.
12. Worktree and sandbox isolation.
13. Remote GitHub or GitLab boundary.
14. Criteria for Dart Workspace and Melos adoption.

## Recommended Product Position

Build **Contingent Review** as a strongly isolated, package-ready feature whose domain can be extracted into pure Dart after the behavior and contracts are proven. Begin local, read-only, snapshot-bound, and fully instrumented. Deliver one reviewer before multiple reviewers, deterministic evidence before debate, and visible disagreement before any remediation workflow.

Prompt should not claim that multiple agents make review reliable. It should demonstrate that transparent disagreement, external evidence, and measured model diversity reduce integration risk or human review time.

The next planning deliverable should turn this report into a product specification, architecture decision records, acceptance tests, and a reviewable commit plan before implementation begins.

## Sources

### Official Product Documentation

- GitHub Copilot Code Review: https://docs.github.com/en/copilot/concepts/agents/code-review
- Claude Code Review: https://code.claude.com/docs/en/code-review
- OpenAI Codex Code Review: https://developers.openai.com/codex/cloud/code-review.md
- Gemini Code Assist for GitHub: https://docs.cloud.google.com/gemini/docs/code-review/review-repo-code
- Cursor Bugbot: https://cursor.com/docs/bugbot
- Amazon Q Developer Code Reviews: https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/code-reviews.html
- CodeRabbit Code Review: https://docs.coderabbit.ai/guides/code-review-overview
- Qodo Code Review: https://docs.qodo.ai/code-review/overview
- PR-Agent: https://github.com/The-PR-Agent/pr-agent
- Greptile: https://www.greptile.com/
- Graphite: https://graphite.dev/features
- Snyk Code: https://snyk.io/product/snyk-code/
- Semgrep Code: https://semgrep.dev/docs/semgrep-code/overview
- GitHub CodeQL: https://docs.github.com/en/code-security/code-scanning/introduction-to-code-scanning/about-code-scanning-with-codeql
- OpenCode Server: https://opencode.ai/docs/server/
- OpenCode Agents: https://opencode.ai/docs/agents/
- OpenCode Permissions: https://opencode.ai/docs/permissions/
- Dart Pub Workspaces: https://dart.dev/tools/pub/workspaces
- Melos: https://melos.invertase.dev/

### Research

- Wang et al., *Self-Consistency Improves Chain of Thought Reasoning in Language Models*, ICLR 2023: https://arxiv.org/abs/2203.11171
- Madaan et al., *Self-Refine: Iterative Refinement with Self-Feedback*: https://arxiv.org/abs/2303.17651
- Du et al., *Improving Factuality and Reasoning in Language Models through Multiagent Debate*: https://arxiv.org/abs/2305.14325
- Irving, Christiano, and Amodei, *AI Safety via Debate*: https://arxiv.org/abs/1805.00899
- Lightman et al., *Let's Verify Step by Step*: https://arxiv.org/abs/2305.20050
- Zheng et al., *Judging LLM-as-a-Judge with MT-Bench and Chatbot Arena*, NeurIPS 2023: https://arxiv.org/abs/2306.05685
- Huang et al., *Large Language Models Cannot Self-Correct Reasoning Yet*, ICLR 2024: https://arxiv.org/abs/2310.01798
- Sharma et al., *Towards Understanding Sycophancy in Language Models*: https://arxiv.org/abs/2310.13548
- Wang et al., *Mixture-of-Agents Enhances Large Language Model Capabilities*: https://arxiv.org/abs/2406.04692
- Jimenez et al., *SWE-bench: Can Language Models Resolve Real-World GitHub Issues?*, ICLR 2024: https://arxiv.org/abs/2310.06770

### Governance and Supply Chain

- NIST AI Risk Management Framework: https://www.nist.gov/itl/ai-risk-management-framework
- NIST Generative AI Profile: https://doi.org/10.6028/NIST.AI.600-1
- SLSA Specification 1.2: https://slsa.dev/spec/v1.2/
- Sigstore documentation: https://docs.sigstore.dev/
- GitHub Dependency Review: https://docs.github.com/en/code-security/supply-chain-security/understanding-your-software-supply-chain/about-dependency-review
- OpenSSF Scorecard: https://openssf.org/projects/scorecard/
