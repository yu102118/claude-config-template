---
name: env-setup
description: UniSave environment configuration — required .env vars, dev vs Render differences, and first-run setup sequence
---

# Environment Setup

## Required `.env` File
Create `.env` in the project root (next to `manage.py`):
```env
GOOGLE_API_KEY=your_gemini_api_key_here
SECRET_KEY=your_django_secret_key_here
DATABASE_URL=sqlite:///db.sqlite3
```

| Variable | Required | Notes |
|----------|----------|-------|
| `GOOGLE_API_KEY` | Yes | Gemini 2.0 Flash API key from Google AI Studio |
| `SECRET_KEY` | Yes | Any long random string for Django signing |
| `DATABASE_URL` | No | Defaults to `sqlite:///db.sqlite3` if omitted |

`.env` is in `.gitignore` — never commit it.

## First-Run Setup
```bash
# 1. Install Python deps
pip install -r requirements.txt

# 2. Apply DB migrations
python manage.py migrate

# 3. Install frontend deps
cd frontend && npm install && cd ..

# 4. Start both servers (two terminals)
python manage.py runserver          # :8000
cd frontend && npm run dev           # :5173 (proxies /api → :8000)
```

## Render (Production) Environment

Render injects these automatically or via the dashboard:

| Variable | Source | Value |
|----------|--------|-------|
| `RENDER` | Auto-set by Render | Any truthy string |
| `DEBUG` | Render env vars | Omit for `False`; set `'True'` only for debugging |
| `DATABASE_URL` | Render env vars | PostgreSQL connection string |
| `GOOGLE_API_KEY` | Render env vars | Same key as dev |
| `SECRET_KEY` | Render env vars | Different from dev — use a strong random value |

`DEBUG` defaults to `False` on Render unless explicitly set. Never deploy with `DEBUG=True`.

## Sentence-Transformers Model
The embedding model (`all-MiniLM-L6-v2`, ~90 MB) is downloaded on first use and cached:
- **Dev**: cached to `~/.cache/torch/sentence_transformers/`
- **Render**: cached within the container; re-downloaded on each new deploy (cold start adds ~30s)

No additional env var needed — the model name is hardcoded in `core/services/embeddings.py`.

## Gemini Free-Tier Limits
- 15 requests per minute (pipeline budgets 12 RPM)
- If you hit limits frequently during dev, add `DEBUG_SKIP_GEMINI=true` handling or use a paid tier key
