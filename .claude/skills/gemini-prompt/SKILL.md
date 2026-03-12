---
name: gemini-prompt
description: How UniSave calls Gemini — analyze_question interface, required JSON output shape, 3-pass repair, and what not to break when modifying AI behavior
---

# Gemini Integration

## Entry Point
```python
# core/services/ai.py
GeminiService.analyze_question(
    question: str,
    context_chunks: list[Chunk],
) -> dict
```
Returns:
```python
{
    "status":    "VERIFIED" | "CONFLICT" | "NOT_FOUND",
    "ai_answer": "short factual summary string",
    "claims": [
        {
            "quote":       "verbatim text from source",
            "material_id": 1,
            "page_number": 3,
        },
        # …
    ]
}
```
`pipeline.py` passes this dict directly to `TaskResult.objects.update_or_create`. **Never rename these keys.**

## Model
- **Gemini 2.0 Flash** (`gemini-2.0-flash` or equivalent in `GeminiService.MODEL_NAME`)
- Called via `google-generativeai` SDK
- Free-tier: 15 RPM — pipeline rate-limiter holds it to 12 RPM

## Context Building
`GeminiService.build_context(chunks)` formats chunks into:
```
[Material #1]
[Page 3]
chunk text here…

[Material #1]
[Page 4]
more chunk text…
```
This formatted string is the user prompt context. Gemini must locate quotes within it and return `material_id` + `page_number` that match these headers — **do not change the header format** or validation will fail to find the pages.

## Required JSON Output Shape
The prompt instructs Gemini to return **only** a JSON object with exactly these keys. If the prompt is modified:
- Keep `status`, `ai_answer`, `claims` as top-level keys.
- Each claim needs `quote`, `material_id`, `page_number` — `validation.py` looks up `Page.objects.get(material_id=..., page_number=...)`.
- `material_id` must be an integer matching a real `StudyMaterial.pk`.

## 3-Pass JSON Repair (`_parse_response`)
Gemini occasionally returns malformed JSON. The parser tries in order:
1. **Raw parse** — `json.loads(response.text)` directly
2. **Regex extraction** — finds the outermost `{…}` block and parses it
3. **Quote-escaping repair** — fixes unescaped quotes inside string values

If all three fail, returns the fallback dict (`NOT_FOUND`, empty claims). This means:
- Prompt changes that make Gemini output non-JSON (e.g. markdown fences around JSON) can break pass 1 and 2 but pass 3 may still save it.
- Safest: instruct Gemini to return JSON with **no surrounding text**.

## Rate Limiting & Retry
- **pipeline.py** — sliding window limiter, 12 RPM, calls `_rate_limit_wait()` before each `analyze_question`.
- **ai.py** — `ResourceExhausted` caught internally; exponential backoff: 5s → 15s → 45s across 3 attempts; returns fallback on final failure.
- After each backoff, ai.py appends to `pipeline._gemini_call_times` so the sliding window stays in sync.

## What Not to Break
| Invariant | Why |
|-----------|-----|
| Return dict keys `status`, `ai_answer`, `claims` | `pipeline.py` unpacks these directly |
| `claims[].material_id` is an integer | `Page.objects.get(material_id=...)` |
| `claims[].page_number` is an integer | same |
| `claims[].quote` is verbatim source text | `ValidationService` fuzzy-matches it against `Page.text_raw` |
| `GeminiService.analyze_question` signature | `pipeline.py` calls it by position |
