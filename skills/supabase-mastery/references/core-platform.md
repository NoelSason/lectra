# Supabase Core Platform

As of February 24, 2026.

## 1) Platform model

Supabase combines managed PostgreSQL with first-party developer services:

- Data API layer (REST and GraphQL entry points).
- Auth.
- Storage.
- Realtime.
- Edge Functions.
- Observability/usage/billing controls in dashboard.

Treat PostgreSQL as the source of truth. Treat APIs, auth, and storage policies as controlled interfaces over that core.

## 2) API and data access model

Use the Data API for most web/mobile CRUD workflows. Use direct PostgreSQL connections for heavy backend workloads, advanced SQL/session usage, or bulk jobs.

Decision rule:

- Favor Data API for low-friction product development.
- Favor direct Postgres for backend services needing full SQL/session behavior.

## 3) PostgreSQL connection strategy

Supabase supports three practical connection paths:

1. Direct connection.
Use for long-running services and full PostgreSQL feature compatibility.

2. Session pooler (Supavisor session mode, port 5432).
Use when clients need prepared statements and session features while still pooling.

3. Transaction pooler (Supavisor transaction mode, port 6543).
Use for serverless/ephemeral clients at scale. Avoid assumptions requiring session persistence or prepared statements.

## 4) Local development and migration workflow

Preferred loop:

1. `supabase init`
2. `supabase start`
3. `supabase migration new <name>`
4. `supabase db reset` (replay migrations locally)
5. `supabase link --project-ref <project_ref>`
6. `supabase db push` (deploy migrations)

For drift control:

- Use `supabase db pull` only when intentionally importing dashboard-side changes.
- Keep SQL migrations deterministic and idempotent.
- Review `EXPLAIN ANALYZE` on critical queries before prod rollout.

## 5) Branching and environment workflow

Use Supabase branches for isolated database environments tied to feature work.

Recommended pattern:

1. Feature branch per risky schema/policy change.
2. Run integration tests and auth/RLS checks against branch endpoints.
3. Merge only after migration + policy validation.

## 6) Backup and recovery posture

Treat backup strategy as part of release readiness:

- Verify backup type and retention for the active plan.
- Enable Point in Time Recovery where required.
- Rehearse restore drills and document RTO/RPO targets.

Never assume restore readiness without a rehearsal.

## 7) Billing, quotas, and spend control

Billing and usage caps are plan-dependent and change over time.

Operational guardrails:

1. Set spend cap and alerts for each production project.
2. Monitor compute/storage/egress/realtime/function usage weekly.
3. Revalidate pricing assumptions before major launches.

## 8) Source links

- https://supabase.com/docs
- https://supabase.com/docs/guides/api
- https://supabase.com/docs/guides/database/connecting-to-postgres
- https://supabase.com/docs/guides/local-development
- https://supabase.com/docs/guides/deployment/branching
- https://supabase.com/docs/guides/platform/backups
- https://supabase.com/docs/guides/platform/manage-your-usage/billing
- https://github.com/supabase/supabase
