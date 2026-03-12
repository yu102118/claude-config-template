---
name: debug-pipeline
description: Diagnose UniSave pipeline failures — NOT_FOUND verdicts, ResourceExhausted errors, embedding failures, retrieval returning 0 chunks
---

# Debug Pipeline

## When to Use This Skill
- All questions return `NOT_FOUND` after task completes
- Logs show `ResourceExhausted` or Gemini fallback returned
- Retriever logs `ZERO chunks in DB` or returns empty list
- Embedding generation silently skipped during ingestion
- `subject_id` mismatch between material upload and task creation

---

## Checklist

### 1. Chunks exist for the subject?
```python
# Django shell: python manage.py shell
from core.models import Chunk, StudyMaterial
mat_ids = StudyMaterial.objects.filter(subject_id=<id>).values_list('id', flat=True)
print(Chunk.objects.filter(page__material_id__in=mat_ids).count())
# 0 → ingestion failed or wrong subject_id
```

### 2. Embeddings were generated?
```python
from core.models import Chunk
total = Chunk.objects.filter(page__material_id__in=mat_ids).count()
with_emb = Chunk.objects.filter(page__material_id__in=mat_ids, embedding__isnull=False).count()
print(f"{with_emb}/{total} chunks have embeddings")
# If 0 → sentence-transformers failed at ingestion time; re-upload the material
```

### 3. Gemini quota / ResourceExhausted?
- Check logs for: `ResourceExhausted: exponential backoff` (ai.py retry)
- Check logs for: `Rate limiter: sleeping` (pipeline.py sliding window)
- Free tier limit: 15 RPM. Pipeline uses 12 RPM budget with sliding window.
- If hitting limit consistently: reduce `_RATE_LIMIT` in `pipeline.py` or upgrade Gemini tier.

### 4. Subject ID correct?
```python
from core.models import ExamTask, StudyMaterial
task = ExamTask.objects.get(pk=<task_id>)
mats = StudyMaterial.objects.filter(subject=task.subject)
print(f"Task subject: {task.subject} | Materials: {mats.count()}")
# 0 materials → material uploaded to wrong subject
```

### 5. Ingestion actually ran?
```python
from core.models import Page, StudyMaterial
m = StudyMaterial.objects.get(pk=<material_id>)
print(Page.objects.filter(material=m).count())
# 0 → ingestion failed; check logs for DocumentProcessingError
```

---

## Log Signatures to Search

| Symptom | Log pattern |
|---------|-------------|
| No chunks | `ZERO chunks in DB for materials` |
| No materials | `Subject X has NO materials in DB` |
| Gemini retry | `ResourceExhausted: exponential backoff` |
| Rate limiter active | `Rate limiter: X.Xs until window clears` |
| Embedding skipped | `Embedding model unavailable` |
| Embedding error | `Embedding failed for material` |
| Ingestion error | `DocumentProcessingError` |
| Gemini gave up | `Gemini rate limit hit after 3 attempts; returning fallback` |

---

## Quick Re-ingest
If chunks exist but embeddings are missing (pre-embedding upload):
1. Delete the material via `DELETE /api/materials/<id>/` (if endpoint exists) or Django admin
2. Re-upload the same file — ingestion will now batch-embed all chunks
3. Re-submit the exam task

---

## Fallback Behavior Summary
- **No chunks** → Gemini skipped, result saved as `NOT_FOUND` immediately
- **Embedding model down** → retriever falls back to keyword-only (still works)
- **ResourceExhausted** → ai.py retries with 5s/15s backoff; after 3 attempts returns fallback dict (NOT_FOUND)
- **Invalid JSON from Gemini** → 3-pass JSON repair in `ai.py._parse_response`; if all fail, returns fallback
