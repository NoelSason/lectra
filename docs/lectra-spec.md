# Lectra Pre-Production Specification (iPadOS Pivot)

This document outlines the architecture and specifications for the Lectra iPad app following its pivot to a GoodNotes-style companion for the Canvascope ecosystem.

---

## 1. Product Blueprint

### What is Lectra?
Lectra is a high-performance, premium iPad application designed specifically for Apple Pencil. It acts as the "analog" extension of the Canvascope digital ecosystem. When students encounter lecture slides, homework PDFs, or readings in Canvascope (on their computer), they can push them directly to Lectra. 

On Lectra, they handwrite their notes seamlessly. When done, the document syncs back to Canvascope for easy viewing and reference on their desktop or Chrome extension.

### Core Workflows
1. **Push (Canvascope Chrome Extension)**: Adding a "Send to Lectra" button on Canvas PDF viewers. Uploads raw PDF to Supabase.
2. **Fetch (Lectra iPad)**: Pulls the PDF from Supabase locally.
3. **Annotate (Lectra iPad)**: The core user experience. Smooth, lag-free Apple Pencil writing over PDFs using PencilKit and PDFKit.
4. **Sync (Lectra iPad)**: Flattens strokes onto the PDF and uploads the `annotated` version back to Supabase.
5. **Review (Canvascope Web/Extension)**: Viewing the annotated PDF on the desktop.

---

## 2. Architecture & Data Model

We utilize the existing Canvascope Supabase project for backend infrastructure.

### Database Schema Overrides
In the existing `synced_items` table (which is used for generic sync data), we introduce a strict contract for PDFs:

- `item_type`: `'pdf_document'`
- `item_data` (JSONB format):
  ```json
  {
    "title": "CS161_Midterm_Review.pdf",
    "courseId": 123456,
    "sourceUrl": "https://bcourses.berkeley.edu/...",
    "storagePath": "user-uuid/lectra_documents/raw-xxx.pdf",
    "annotatedStoragePath": "user-uuid/lectra_documents/annotated-xxx.pdf",
    "status": "pending_annotation" // "pending_annotation" | "annotated" | "archived"
  }
  ```

### Storage Bucket
A new private bucket named `lectra_documents` will hold the binary `.pdf` files. RLS policies must ensure users can only read/write their own PDF objects.

### Apple Stack
- **UI**: SwiftUI
- **Renderer**: PDFKit (`PDFView`)
- **Drawing**: PencilKit (`PKCanvasView`)
- **Local Database**: SwiftData (caching `synced_items` metadata)
- **Backend / Sync**: Supabase Swift SDK

---

## 3. The Synchronization Loop

1. **Local Representation**: `DocumentItem` (SwiftData Model) mirrors the Supabase `synced_items` row. 
    - Has an `enum` for download state: `.cloudRemote`, `.downloading`, `.downloadedLocalReady`, `.syncingUp`.
2. **Offline-First Storage**: Downloaded PDFs are stored in the app's `DocumentDirectory` to ensure they are available without a network connection.
3. **Merging Strokes**: When the user finishes a session or leaves the editor, we extract the `PKDrawing` data, render it into an image or vector context, and draw it onto the respective `PDFPage` bounds. We save a new, flattened PDF file locally.
4. **Uploading**: We upload this new PDF to the `annotatedStoragePath` on Supabase Storage. We then update the Database row's `status` to `annotated`.

---

## 4. UI/UX Wireframes

### Home View (Document Browser)
- **Header**: "Lectra", user profile avatar.
- **Filters**: "New", "Annotated", "Archived".
- **Grid**: Large thumbnail previews of PDFs.
    - If `status == pending_annotation`, show a subtle "New" badge or blue dot.
    - Show the Course Name (via `courseId`) or document string title under the thumbnail.

### Editor View
- **Background**: The `PDFView`, scaled to fit safely.
- **Overlay**: `PKCanvasView`. Critical engineering work: ensuring the canvas view properly transforms its strokes when the user zooms or pans the underlying PDF.
- **Toolbar**: 
    - Top Left: `< Back` (Triggers sync).
    - Top Right: `Export`, `Settings` (Optional for v1).
    - Floating (or standard `PKToolPicker`): Pen, Highlighter, Eraser, Lasso, Color Palette. This should seamlessly integrate with iOS standard behavior but must match a premium aesthetic.

### Page Navigation & Auto-Append Behavior
- **Primary Navigation**: In read/write mode, horizontal swipe gestures move between pages.
- **End-of-Document Gesture**: If the user performs a left swipe while already on the final page, Lectra should append a new blank page and immediately navigate to it.
- **Input Safety Rule**: Auto-append is only triggered by an intentional page-navigation swipe (not during an active Pencil stroke) so drawing gestures do not accidentally create pages.
- **Feedback**: Show lightweight confirmation (for example, a subtle toast such as `New page added`) to preserve user confidence while keeping flow uninterrupted.

---

## 5. Major Engineering Risks (Crucial Considerations)
1. **PencilKit + PDFKit Alignment**: Keeping stroke coordinates perfectly aligned with the PDF pages during zoom levels and scrolling. This traditionally requires complex subclassing of `PDFView` or synchronizing coordinate spaces.
2. **Memory Overload**: `PKCanvasView` over large PDFs (e.g., 50-100+ pages) can cause jetsam events (memory limits). You must design a paginated or tiled canvas approach if single-view overloads memory.
3. **Offline Sync Concurrency**: Handling edge cases where the user starts annotating before the upload/download finishes, or edits offline and reconnects later causing conflicts. (For v1: Local edits always win).
