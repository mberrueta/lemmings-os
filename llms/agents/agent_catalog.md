---
title: Agent Catalog
---

# Agent Catalog

Brief descriptions of each agent and when to use them.

## Audit Agents

- `audit_accessibility.md` (`audit-accessibility`): Accessibility (a11y) auditor for web/mobile-first Phoenix + LiveView apps. Reviews UI for keyboard navigation, focus management, ARIA semantics, and WCAG compliance.

- `audit_pr_elixir.md` (`audit-pr-elixir`): Staff-level PR reviewer for Elixir/Phoenix backends. Reviews correctness, design quality, security, performance, logging, and test coverage. Pays particular attention to OTP supervision correctness and World scoping.

- `audit_security.md` (`audit-security`): Security reviewer for features and code changes. Analyzes authentication, authorization, input validation, secrets management, OWASP risks, and PII safety.

- `audit_seo.md` (`audit-seo`): SEO reviewer for web pages and implementations. Covers technical SEO, on-page optimization, structured data, and social media previews.

- `audit_ui_inventory.md` (`audit-ui-inventory`): UI inventory builder for Phoenix LiveView apps. Creates and maintains comprehensive documentation of pages, components, and UI patterns.

## Development Agents

- `dev_backend_elixir_engineer.md` (`dev-backend-elixir-engineer`): Senior backend engineer for Elixir/Phoenix. Implements schemas, contexts, queries, OTP processes, background jobs, observability, and performance optimizations. Must enforce World scoping in all context APIs.

- `dev_db_performance_architect.md` (`dev-db-performance-architect`): Database architect for schema design and performance. Handles indexes, query optimization, migrations, and Postgres tuning.

- `dev_frontend_ui_engineer.md` (`dev-frontend-ui-engineer`): Frontend engineer for Phoenix LiveView. Implements UI components, Tailwind/daisyUI styling, LiveView hooks, and responsive accessible interfaces.

- `dev_logging_daily_guardian.md` (`dev-logging-daily-guardian`): Logging quality guardian for day-to-day development. Reviews diffs for logging consistency, adds structured events with hierarchy metadata, and normalizes metadata safely.

## Documentation Agents

- `docs_feature_documentation_author.md` (`docs-feature-documentation-author`): Feature documentation writer. Creates and updates user-facing documentation aligned with actual application behavior.

- `docs_research_specialist.md` (`docs-research-specialist`): Documentation and research specialist. Researches external docs, standards, and APIs, delivering authoritative summaries with citations.

## Product & Planning Agents

- `po_analyst.md` (`po-analyst`): Product owner analyst for feature specifications. Validates and expands specs against codebase, creates user stories, and defines comprehensive acceptance criteria.

- `tl_architect.md` (`tl-architect`): Technical lead architect. Transforms validated feature specs into executable technical plans with discrete tasks, dependencies, and implementation strategy.

## QA & Testing Agents

- `qa_elixir_test_author.md` (`qa-elixir-test-author`): QA-driven Elixir test writer. Converts scenarios into ExUnit tests with proper test layers (unit, integration, LiveView, OTP process tests), minimal factories, and actionable failures.

- `qa_test_scenarios.md` (`qa-test-scenarios`): Test scenario designer. Defines what to test (scenarios, acceptance criteria, edge cases, regressions) without writing implementation code.

## Release Management Agents

- `rm_release_manager.md` (`rm-release-manager`): Release manager for Elixir/Phoenix apps. Prepares release notes, runbooks, migration risk assessments, and rollback plans.
