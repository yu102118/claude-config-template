# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

UniSave is an exam validation tool for university students. Users upload lecture materials (PDF/DOCX/PPTX), then submit exam questions. The backend uses Google Gemini to extract verbatim answers strictly from the uploaded materials, returning verified citations with page references.

## Commands

### Backend (Django)
```bash
# Run dev server
python manage.py runserver

# Apply migrations
python manage.py migrate

# Create new migrations after model changes
python manage.py makemigrations

# Open Django shell
python manage.py shell

# Run tests
python manage.py test core

# Collect static files (for deployment)
python manage.py collectstatic --no-input
```

### Frontend (React + Vite)
```bash
cd frontend

# Install dependencies
npm install

# Dev server (port 5173)
npm run dev

# Build for production
npm run build

# Lint
npm run lint
```

### Environment
Create a `.env` file in the project root:
```
GOOGLE_API_KEY=your_key_here
SECRET_KEY=your_django_secret
DATABASE_URL=sqlite:///db.sqlite3  # optional, defaults to sqlite
```

## Architecture

### Data Model (`core/models.py`)
```
Subject  ──┬──  StudyMaterial  ──  Page  ──  Chunk
           └──  ExamTask  ──  TaskQuestion  ──  TaskResult
```

- **Subject**: Groups materials and exam tasks by academic subject.
- **StudyMaterial**: Uploaded lecture file (PDF/DOCX/PPTX). Ingestion runs synchronously on upload.
- **Page**: One page/slide extracted from a StudyMaterial; stores `text_raw` and `text_norm` (lowercased).
- **Chunk**: ~1000-char overlapping text fragment of a Page, used for keyword retrieval.
- **ExamTask**: An exam paper with `pending → processing → completed` status.
- **TaskQuestion**: A single question within an ExamTask.
- **TaskResult**: AI verdict (`VERIFIED` / `CONFLICT` / `NOT_FOUND`), answer text, and JSON quotes list with `bboxes` for PDF highlight coordinates.

### Backend Services (`core/services/`)

| File | Responsibility |
|------|---------------|
| `ingestion.py` | Extracts text from PDF/DOCX/PPTX → creates Page + Chunk rows. Entry point: `process_document(material_id)`. |
| `retriever.py` | Keyword-frequency search over Chunks for a Subject. Entry point: `get_top_chunks_for_subject(subject_id, question, top_k=10)`. |
| `ai.py` | Calls Gemini 2.0 Flash with strict JSON output. Entry point: `GeminiService.analyze_question(question, chunks)`. |
| `validation.py` | Verifies AI-returned quotes exist verbatim on their claimed page; returns fuzzy match score and bounding boxes. |
| `pipeline.py` | Orchestrates retriever → AI → validation → save for all questions of an ExamTask. Runs in a `daemon=True` background thread. |

### API Endpoints (`core/urls.py`)
```
POST   /api/subjects/          Create subject
GET    /api/subjects/          List subjects
POST   /api/materials/         Upload material (triggers synchronous ingestion)
GET    /api/materials/         List materials
POST   /api/tasks/             Create task + start background pipeline → 202 Accepted
GET    /api/tasks/             List tasks
GET    /api/tasks/{id}/        Poll task status + nested results
DELETE /api/tasks/{id}/        Delete task
```

### Frontend (`frontend/src/`)
- `App.tsx`: Main dashboard — subject/material management, task creation, task history list.
- `pages/TaskResultPage.tsx`: Polls `GET /api/tasks/{id}/` until completed; displays per-question verdicts and quotes.
- `services/api.ts`: All fetch calls; `API_BASE_URL = '/api'` (proxied by Vite in dev, served by Django in production).
- Vite proxies `/api` → `http://localhost:8000` in dev mode.

### Deployment (Render)
- `build.sh` runs: `pip install -r requirements.txt`, `collectstatic`, `migrate`.
- Static files served by WhiteNoise middleware.
- `RENDER` env var is set automatically; `DEBUG` defaults to `False` on Render unless explicitly set to `'True'`.
- Database URL is read from `DATABASE_URL` env var via `dj-database-url`.

### Key Implementation Details
- **Gemini rate limiting**: Pipeline sleeps 4s between questions to stay under free-tier (15 req/min). On `ResourceExhausted`, retries up to 3× with 20s sleep.
- **JSON repair**: `GeminiService._parse_response` has a 3-pass parser (raw → regex extraction → quote-escaping repair) so malformed AI JSON rarely causes failures.
- **Retrieval is keyword-based** (no embeddings). The retriever extracts keywords from the question, scores all Chunks in the Subject by keyword frequency, returns top-K. If zero chunks are found, Gemini is skipped and result is `NOT_FOUND`.
- **DOCX/PPTX "pages"**: These formats have no native page concept. DOCX is split into ~800-word sections; each PPTX slide becomes one "page". `page_number` maps back to these virtual pages.
