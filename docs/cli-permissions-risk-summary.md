# CLI Permission Bypass Risk Summary

## What this is

Some coding agents and AI-assisted CLIs can be run in modes that reduce or remove interactive permission prompts for actions such as:

- reading files
- editing files
- running shell commands
- accessing git
- creating or deleting resources

In practice, this can feel similar to a "dangerously skip permissions" mode. Different tools use different names, but the underlying concern is the same: the operator may give the agent broad authority without a per-action approval step.

## Why this matters

When approvals are skipped, the main safety layer shifts from "the human must confirm each risky step" to "the human must trust the initial configuration and instructions."

That creates a few obvious risks:

- unintended file edits can happen faster and across more files
- destructive shell commands become easier to trigger accidentally
- sensitive files may be read or included in outputs without a pause for review
- git operations can stage, commit, or otherwise modify repository state before the user notices
- automation can chain multiple risky actions together in one run

## Why users compare this to Claude Code or Cursor

Users often raise this concern because agentic tools commonly support some version of:

- auto-approve or reduced-approval execution
- broad workspace trust
- shell access from within the agent
- scripted or CLI-first execution outside the usual editor confirmation UX

Whether the exact feature is called `dangerously-skip-permissions`, `auto-run`, `full access`, or something similar, the governance question is the same:

> Can the agent perform meaningful system or repository actions without a fresh human confirmation?

If the answer is yes, the mode should be treated as high trust.

## Real concern areas

The biggest practical concerns are usually:

- deleting or overwriting source files
- running dangerous shell commands
- modifying git state in ways that are hard to review quickly
- reading local secrets from files such as `.env`, config files, tokens, or credentials
- opening networked tooling or external integrations with too much authority

## What makes it "dangerous"

Skipping approvals is not automatically reckless, but it becomes dangerous when combined with one or more of these conditions:

- a large or unfamiliar repository
- vague instructions
- direct shell access
- write access outside the intended folder
- access to secrets or deployment credentials
- permission to run long command chains without review

The risk is highest when an agent can both decide *what* to do and execute it immediately.

## Recommended guardrails

If this is a concern for Cursor-style workflows, use these guardrails:

- keep the agent scoped to the project directory only
- prefer approval-required modes for shell and destructive actions
- avoid giving the agent access to secrets unless absolutely necessary
- separate read-only exploration from write-capable execution
- review diffs before commit or push
- avoid unattended runs with broad filesystem and shell permissions
- use environment separation for risky repos or production-connected tooling
- log or document when high-trust modes are enabled

## Practical policy suggestion

A simple internal policy could be:

1. Default to approval-based execution.
2. Allow reduced-approval modes only for trusted local development tasks.
3. Never use full-trust or approval-skipping modes in repos containing production credentials or critical infrastructure access.
4. Require human review before commit, release, or deployment actions.

## Bottom line

Yes, this is a legitimate concern.

If a coding CLI or editor agent can effectively bypass per-action permissions, it should be treated like a high-trust automation tool, not like a normal autocomplete feature. The core risk is not the brand name of the tool; it is the combination of autonomous decision-making, shell access, write access, and reduced human confirmation.
