---
name: project-conventions
description: UniSave backend conventions — stack, pipeline flow, verdict types, and interface contracts to never break
---

# UniSave Project Conventions

## Stack
- **Backend**: Django 5.1, Django REST Framework
- **Database**: SQLite (dev) / PostgreSQL (Render prod) via `dj-database-url`
- **AI**: Gemini 2.0 Flash via `google-generativeai`
- **Embeddings**: `sentence-transformers` / `all-MiniLM-L6-v2` (384-dim, local CPU)
- **PDF**: PyMuPDF (`fitz`), validation via `rapidfuzz`
- **Server**: Gunicorn + WhiteNoise (static files)

## Data Model
```
Subject ──┬── StudyMaterial ── Page ── Chunk
          └── ExamTask ── TaskQuestion ── TaskResult
```
- `Chunk.embedding` — nullable JSONField (384 floats). Null = pre-embedding data, falls back to keyword-only retrieval.
- `TaskResult.status` — one of three verdicts (see below).

## Verdict Types
| Verdict | Meaning |
|---------|---------|
| `VERIFIED` | AI found the answer verbatim in the uploaded material |
| `CONFLICT` | AI found contradictory information across sources |
| `NOT_FOUND` | No relevant chunks found OR Gemini could not locate an answer |

## Pipeline Flow
```
POST /api/tasks/
  → create ExamTask (status: pending)
  → start daemon thread → process_exam_task(task_id)
      for each TaskQuestion:
        1. _rate_limit_wait()               ← sliding window, 12 RPM
        2. get_top_chunks_for_subject()     ← hybrid semantic + keyword
        3. GeminiService.analyze_question() ← Gemini 2.0 Flash
        4. ValidationService.verify_citation() per claim
        5. save TaskResult
  → status: completed
```

## Interface Contracts — Never Break
- `get_top_chunks_for_subject(subject_id, question, top_k) -> list[Chunk]`
  — signature and return type must remain stable; `pipeline.py` and tests depend on it.
- `GeminiService.analyze_question(question, context_chunks) -> dict`
  — returns `{"status": str, "ai_answer": str, "claims": list}`.

## Common Commands
```bash
# Run tests
python manage.py test core

# Dev server
python manage.py runserver

# After model changes
python manage.py makemigrations
python manage.py migrate

# Production static files
python manage.py collectstatic --no-input

# Django shell
python manage.py shell
```

## Services Map
| File | Responsibility |
|------|---------------|
| `core/services/ingestion.py` | PDF/DOCX/PPTX → Pages → Chunks + embeddings |
| `core/services/embeddings.py` | Singleton `SentenceTransformer` loader |
| `core/services/retriever.py` | Hybrid cosine + keyword chunk ranking |
| `core/services/ai.py` | Gemini call + JSON repair + retry |
| `core/services/validation.py` | Fuzzy quote matching + PDF bounding boxes |
| `core/services/pipeline.py` | Orchestration + rate limiter |
