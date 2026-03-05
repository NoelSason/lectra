# Technical Context: Database Schema & Data Models

This file dictates the single source of truth for the iPad Apple Pencil notes app data integration with Canvascope.

## 1. Supabase Postgres Schema (Production)

We rely on the existing Canvascope backend.

```sql
-- Users (managed by Supabase Auth)
-- ... standard table representation

-- Synced Items (The Core Document Store)
-- We enforce this contract when item_type = 'pdf_document'
create table public.synced_items (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references public.users(id) on delete cascade not null,
  item_type text not null, -- must be 'pdf_document'
  item_data jsonb not null default '{}'::jsonb,
  sync_status text default 'synced',
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- RLS Policies are ENABLED for all tables.
-- Users can only SELECT/INSERT/UPDATE/DELETE rows where auth.uid() = user_id.
```

## 2. 'pdf_document' JSON Schema
When fetching rows from `synced_items`, decode the `item_data` into this Swift `Codable` structure:

```json
{
  "title": "CS161_Midterm_Review.pdf",
  "courseId": 123456,
  "sourceUrl": "https://bcourses.berkeley.edu/.../download",
  "storagePath": "user-uuid/lectra_documents/imported_from_canvascope/2026/03/<row-id>.pdf",
  "annotatedStoragePath": null,
  "status": "pending_annotation",
  "sourcePlatform": "canvascope_extension",
  "sourceKind": "canvas_pdf_import"
}
```

## 3. Storage Buckets (File Blobs)
- **Bucket**: `lectra_documents` (Private RLS-enabled)
- **Flow**:
  1. The Canvascope Chrome extension uploads a file to `<user-id>/lectra_documents/imported_from_canvascope/<yyyy>/<mm>/<row-id>.pdf`.
  2. The extension inserts a row into `synced_items` pointing to that `storagePath` with `status: pending_annotation`.
  3. The Lectra iPad App downloads the PDF from `storagePath`.
  4. The user annotates using PencilKit.
  5. Lectra locally merges the strokes out to a flattened PDF.
  6. Lectra uploads the new PDF to a user-scoped annotated path and sets `annotatedStoragePath`.
  7. Lectra updates the `<row-id>` changing the `status` to `annotated` and populating `annotatedStoragePath`.

## 4. UI/Design Tokens (GoodNotes Style)
- **Primary Color:** Canvascope Red (`#E02520`) - Use for active tools, high-contrast actions.
- **Backgrounds:** Minimal dark glass. Let the PDF take up 95% of the screen.
- **Navigation:** Floating toolbars to maximize writing space. Auto-hide nav bars when drawing starts.
- **Constraints**: Handle massive memory usage. Ensure Pencil strokes do not overload the jetsam process when layering over 100+ page PDFs. If necessary, render the `PDFView` background to a tiled system.
