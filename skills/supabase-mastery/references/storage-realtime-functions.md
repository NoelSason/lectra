# Supabase Storage, Realtime, and Edge Functions

As of February 24, 2026.

## 1) Storage design

Supabase Storage is S3-compatible object storage integrated with Postgres metadata and RLS.

Bucket types:

- Public buckets for globally readable assets.
- Private buckets for authenticated or signed access.

Default posture:

1. Prefer private buckets unless content is intentionally public.
2. Enforce access through `storage.objects` policies.
3. Use signed URLs for controlled time-limited access to private objects.

Policy design reminders:

- Keep path conventions deterministic (for example tenant/user prefixes).
- Use RLS predicates aligned to ownership/tenant columns.
- Validate upload, read, and delete independently.

## 2) Realtime architecture

Realtime supports three primary patterns:

1. Broadcast for app-defined messages.
2. Presence for online state and collaborative cursors.
3. Postgres Changes for database CDC-driven UI updates.

Practical guidance:

- Use Broadcast for high-volume transient events.
- Use Postgres Changes for canonical state synchronization.
- Partition channels by tenant/resource to control fanout.

Plan-aware limits matter for concurrency and throughput. Reconfirm active quotas in dashboard before launch.

## 3) Edge Functions operations

Supabase Edge Functions run on a globally distributed Deno runtime.

Operational defaults:

1. Keep functions stateless and idempotent for retries.
2. Set secrets with `supabase secrets set`.
3. Read secrets via `Deno.env.get(...)`.
4. Keep privileged operations server-side and key-scoped.

Default secrets available include:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_DB_URL`

## 4) Cross-service integration patterns

1. Storage upload completed -> write metadata row -> broadcast/realtime event.
2. Database trigger/event -> edge function webhook/work queue fanout.
3. Auth claim change -> policy-aware data visibility refresh.

## 5) Reliability checklist

1. Verify bucket policies with positive and negative tests.
2. Load test realtime channels with expected concurrent users.
3. Add dead-letter handling for critical function side effects.
4. Track invocation failures and p95/p99 latency in observability dashboards.

## 6) Platform changes to track

Recent Supabase announcements include major Edge/runtime and observability updates (for example Launch Week 15 and platform changelog entries). Re-check changelog before production architecture decisions.

## 7) Source links

- https://supabase.com/docs/guides/storage
- https://supabase.com/docs/guides/realtime
- https://supabase.com/docs/guides/functions
- https://supabase.com/docs/guides/functions/secrets
- https://supabase.com/docs/guides/platform/manage-your-realtime-limits
- https://supabase.com/launch-week/15
- https://supabase.com/changelog
