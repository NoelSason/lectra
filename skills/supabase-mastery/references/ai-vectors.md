# Supabase AI and Vector Workloads

As of February 24, 2026.

## 1) Core approach

Use PostgreSQL + `pgvector` for retrieval-augmented search and semantic similarity when structured relational joins still matter.

Typical table pattern:

1. Primary entity fields (id, tenant_id, created_at, metadata).
2. `embedding vector(<dimensions>)`.
3. Optional text chunks and source references.

## 2) Index strategy

Supabase `pgvector` guidance highlights:

- Use exact search for very small datasets.
- Add HNSW or IVFFlat indexes for larger approximate nearest-neighbor workloads.
- Re-test recall and latency after index or filter changes.

Filtering caveat:

Applying strict metadata filters plus ANN can reduce candidate quality. Validate retrieval quality with real filter combinations and adjust index strategy accordingly.

## 3) Query design and ranking

Recommended flow:

1. Retrieve top-k by vector similarity within tenant scope.
2. Apply business filters and authorization checks.
3. Rerank with domain-specific scores (freshness, quality, permissions).

Keep authorization in SQL predicates or policies, not only application code.

## 4) Operational practices

1. Store embeddings with model/version metadata.
2. Re-embed incrementally on model upgrades.
3. Measure retrieval quality with a fixed eval set (precision@k, recall@k, latency).
4. Separate offline embedding jobs from latency-sensitive API paths.

## 5) Supabase AI ecosystem notes

Supabase provides AI-focused guidance across embeddings, retrieval, and storage patterns. Some announcements also introduce specialized storage bucket concepts for vector/analytics workloads; verify current production support in docs/changelog before committing architecture.

## 6) Source links

- https://supabase.com/docs/guides/ai
- https://supabase.com/docs/guides/database/extensions/pgvector
- https://supabase.com/docs/guides/database/extensions
- https://supabase.com/changelog
- https://supabase.com/launch-week/15
