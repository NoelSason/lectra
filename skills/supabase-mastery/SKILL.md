---
name: supabase-mastery
description: Research-backed workflows for designing, implementing, securing, scaling, and troubleshooting Supabase applications across Postgres, Auth, API keys, Row Level Security, Storage, Realtime, Edge Functions, migrations, branching, and AI/vector workloads. Use when tasks involve Supabase architecture choices, schema or API design, auth and RLS policy work, production hardening, performance tuning, cost controls, or incident debugging.
---

# Supabase Mastery

## Overview

Implement Supabase systems with secure defaults and production discipline.
Load only the reference file needed for the current task to keep context efficient.

## Quick Intake

1. Identify the environment: project ref, region, plan tier, dev/staging/prod.
2. Identify the dominant workload: data API, auth, storage, realtime, functions, or vector/AI.
3. Identify constraints: latency target, compliance requirements, and budget cap.

## Core Workflow

1. Choose architecture and access paths.
- Use [references/core-platform.md](references/core-platform.md) for Data API vs direct Postgres, pooler mode selection, migration workflow, branching, and recovery.

2. Design security first.
- Use [references/security-auth-rls.md](references/security-auth-rls.md) for API key strategy, JWT validation approach, session controls, and RLS policy patterns.

3. Implement product-specific flows.
- Use [references/storage-realtime-functions.md](references/storage-realtime-functions.md) for Storage, Realtime, and Edge Functions design and limits.
- Use [references/ai-vectors.md](references/ai-vectors.md) for vector schema/index choices and AI retrieval patterns.

4. Validate before shipping.
- Run migration and policy checks in staging.
- Validate auth flows with real JWTs and role paths.
- Load test key queries and realtime channels against expected concurrency.

5. Harden operations.
- Set usage alerts and spend caps.
- Document rollback strategy for schema, auth config, and functions.
- Maintain an incident playbook with project ref, dashboards, and rollback commands.

## Fast Decision Rules

1. Use `publishable` keys in clients. Never expose `secret` or `service_role`.
2. Enable RLS on exposed tables and write explicit policies before exposing endpoints.
3. Prefer transaction pooler for highly ephemeral serverless connections.
4. Use direct connections or session pooler when prepared statements or session features are required.
5. Use HNSW/IVFFlat vector indexes only after validating recall and latency with production-like data.
6. Treat pricing and quota numbers as date-sensitive; verify in dashboard before commitments.

## Reference Loader

Load reference files only when needed:

- [references/core-platform.md](references/core-platform.md)
Use for architecture, migrations, connection modes, branching, backups, and cost controls.

- [references/security-auth-rls.md](references/security-auth-rls.md)
Use for API keys, JWT/session behavior, and robust RLS design/performance patterns.

- [references/storage-realtime-functions.md](references/storage-realtime-functions.md)
Use for file access control, realtime architecture, and edge runtime/secret operations.

- [references/ai-vectors.md](references/ai-vectors.md)
Use for pgvector schema/index design and retrieval quality tuning.

## Output Standard

When answering Supabase requests with this skill:

1. State architecture and security assumptions explicitly.
2. Provide migration-safe implementation steps.
3. Include verification steps and rollback notes.
4. Flag date-sensitive details (pricing, limits, platform changes) with explicit dates.
