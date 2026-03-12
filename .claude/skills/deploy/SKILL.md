---
name: deploy
description: Deploy UniSave to Render — test, commit, push, verify. Never deploy with failing tests.
disable-model-invocation: true
---

# Deploy to Render

> **Only invoke this skill with `/deploy`.**
> Never deploy with failing tests. Never skip the checklist.

---

## Pre-Deploy Checklist

```bash
# 1. Run tests — must be green
python manage.py test core --verbosity=2

# 2. Check for pending migrations
python manage.py migrate --check

# 3. Verify static files collect cleanly
python manage.py collectstatic --no-input --dry-run
```

If any step fails → **stop**. Fix before proceeding.

---

## Deploy Steps

```bash
# 1. Stage and commit
git add <files>
git commit -m "your message"

# 2. Push to main (Render auto-deploys on push)
git push origin main

# 3. Watch Render build logs
#    Build runs: pip install -r requirements.txt → collectstatic → migrate
#    Look for: "Build successful" and "Deploy live"
```

---

## Verify After Deploy

- Open the Render dashboard → **Logs** tab
- Confirm no `ERROR` or `Exception` lines in startup logs
- Hit `GET /api/subjects/` — should return 200
- Submit a test exam task and poll `GET /api/tasks/<id>/` until `completed`

---

## Render Environment Notes

| Variable | Value |
|----------|-------|
| `RENDER` | Set automatically by Render — triggers production mode |
| `DEBUG` | Defaults to `False` on Render unless explicitly `'True'` |
| `DATABASE_URL` | PostgreSQL connection string — set in Render env vars |
| `GOOGLE_API_KEY` | Gemini key — set in Render env vars |
| `SECRET_KEY` | Django secret — set in Render env vars |

- Static files served by **WhiteNoise** — no separate static server needed
- `sentence-transformers` model (`all-MiniLM-L6-v2`, ~90 MB) downloads on first request and caches to `~/.cache/torch/`; expect ~30s extra on cold start

---

## What `build.sh` Does
```bash
pip install -r requirements.txt
python manage.py collectstatic --no-input
python manage.py migrate
```
Migrations run automatically on every deploy — safe because all migrations are additive (nullable fields only).

---

## Rollback
If the deploy breaks production:
```bash
# Revert to previous commit and force-push
git revert HEAD
git push origin main
```
Or use Render's **Manual Deploy** → select a previous successful deploy from the dashboard.
