---
name: add-model-or-migration
description: Add Django models or fields to UniSave — when to makemigrations, null/blank rules, migration safety, and the existing model hierarchy
---

# Add Model or Migration

## Existing Model Hierarchy
```
Subject  ──┬──  StudyMaterial  ──  Page  ──  Chunk
           └──  ExamTask  ──  TaskQuestion  ──  TaskResult
```
All models live in `core/models.py`. There is one app: `core`.

## Adding a New Field

### null / blank rules
| Field type | `null=` | `blank=` |
|------------|---------|---------|
| `CharField`, `TextField` | `False` (use `default=""`) | `True` if optional |
| `JSONField` | `True` if optional | `True` |
| `ForeignKey`, `OneToOneField` | `True` if optional | `False` |
| `FloatField`, `IntegerField` | `True` if optional | `False` |

Never add a non-nullable field without a `default` — the migration will fail on existing rows.

### Sequence
```bash
# 1. Edit core/models.py
# 2. Generate migration
python manage.py makemigrations core

# 3. Review the generated file in core/migrations/
# 4. Apply
python manage.py migrate
```

Always review the generated migration before applying — confirm it only touches the fields you changed.

## Adding a New Model

1. Define the class in `core/models.py` (keep related models near each other).
2. Add `related_name` on every `ForeignKey` — use the plural noun of the child, e.g. `related_name='chunks'`.
3. Add a `Meta.ordering` so querysets are deterministic.
4. Add `__str__` returning a human-readable string.
5. Run `makemigrations` then `migrate`.
6. If the model needs a DRF serializer, add it to `core/serializers.py` and wire a viewset in `core/views.py` + `core/urls.py`.

## Migration Safety Rules
- **Additive only** on deployed data: add nullable fields or new tables. Never remove or rename columns in a single migration without a multi-step plan.
- **Never edit** a migration file that has already been applied to production — create a new one instead.
- Render runs `migrate` on every deploy (`build.sh`), so all migrations must be backwards-compatible with the previous deploy's code.

## Key Model Details to Know
- `Chunk.embedding` — `JSONField(null=True)`: 384-dim float list. Null = pre-embedding ingestion; retriever falls back to keyword-only.
- `TaskResult.status` choices: `VERIFIED`, `CONFLICT`, `NOT_FOUND` — defined in `TaskResult.Verdict`.
- `ExamTask.status` choices: `pending`, `processing`, `completed` — defined in `ExamTask.Status`.
- `Page.text_norm` — lowercased version of `text_raw`; used by fuzzy validation.
- `StudyMaterial.file` — stored under `media/materials/`; file path resolved in `ingestion.py`.
