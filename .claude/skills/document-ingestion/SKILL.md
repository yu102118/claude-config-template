---
name: document-ingestion
description: How UniSave ingests PDF/DOCX/PPTX files — extractor architecture, virtual pages, chunking parameters, and adding a new file format
---

# Document Ingestion

## Entry Point
```python
# core/services/ingestion.py
process_document(material_id: int) -> dict
# Returns: {'success': bool, 'pages_processed': int, 'chunks_created': int}
```
Called synchronously on `POST /api/materials/` — the HTTP response waits for ingestion to finish.

## Extractor Architecture
```
process_document(material_id)
  ↓ resolve file path (local or temp file)
  ↓ pick extractor by extension
  ├── .pdf  → extract_text_from_pdf()   → PyMuPDF (fitz)
  ├── .docx → extract_text_from_docx()  → python-docx
  └── .pptx → extract_text_from_pptx()  → python-pptx
  ↓ list[PageData(text, width, height, page_number)]
  ↓ for each PageData:
      clean_text() → Page.objects.create()
      chunk_text() → Chunk.objects.create() × N
  ↓ batch embed all chunks (sentence-transformers)
  ↓ Chunk.objects.bulk_update([...], ['embedding'])
```

## Virtual Pages (DOCX / PPTX)
PDF has real page numbers. DOCX and PPTX do not:

| Format | "Page" definition | `page_number` |
|--------|------------------|---------------|
| PDF | Actual PDF page | Real page number |
| DOCX | ~800-word section | Sequential section index (1, 2, 3…) |
| PPTX | One slide | Slide index (1, 2, 3…) |

`page_number` in `TaskResult.quotes` refers to these virtual pages for DOCX/PPTX. PDF highlight coordinates (`bboxes`) only work for PDFs — DOCX/PPTX return empty bboxes.

## Chunking Parameters
```python
CHUNK_SIZE    = 1000   # characters per chunk
CHUNK_OVERLAP = 100    # overlap between adjacent chunks
```
- Splits on sentence boundaries (`.!?`) within the last 200 chars of each chunk when possible.
- Each chunk stored as `Chunk(page=page, chunk_index=idx, chunk_text=ct)`.
- After all chunks are created, embeddings are batch-computed and stored in `Chunk.embedding` (384-dim, nullable).

## Embedding on Ingestion
```python
# After chunk creation loop:
texts = [c.chunk_text for c in created_chunks]
vectors = embed_texts(texts)          # None if model unavailable
if vectors:
    for chunk, vec in zip(created_chunks, vectors):
        chunk.embedding = vec
    Chunk.objects.bulk_update(created_chunks, ['embedding'])
```
If `embed_texts` returns `None` (model not loaded), chunks are saved with `embedding=None` — retriever falls back to keyword-only for those chunks.

## Adding a New File Format
1. Write `extract_text_from_<ext>(file_path: str) -> list[PageData]` in `ingestion.py`.
2. Each `PageData` must provide `text`, `width`, `height`, `page_number`.
3. Register in `EXTRACTORS` dict:
```python
EXTRACTORS = {
    '.pdf':  extract_text_from_pdf,
    '.docx': extract_text_from_docx,
    '.pptx': extract_text_from_pptx,
    '.new':  extract_text_from_new,   # ← add here
}
```
4. No other files need changing — `process_document` picks the extractor automatically.

## Re-ingesting a Material
There is no built-in re-ingest endpoint. To re-ingest (e.g. after adding embeddings):
1. Delete old `Page` rows (cascades to `Chunk`): `Page.objects.filter(material=m).delete()`
2. Call `process_document(m.id)` from the Django shell.
Or: delete and re-upload the material via the UI.
