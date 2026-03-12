---
name: frontend-dev
description: UniSave frontend structure — Vite proxy, API_BASE_URL, TypeScript component layout, and the task polling pattern
---

# Frontend Development

## Stack
- **React** + **TypeScript** + **Vite** (port 5173 in dev)
- All source under `frontend/src/`

## Commands
```bash
cd frontend
npm install       # install deps
npm run dev       # dev server on :5173
npm run build     # production build → frontend/dist/
npm run lint      # ESLint
```

## File Structure
```
frontend/src/
├── App.tsx                   # Main dashboard
│   └── subject list, material upload, task creation, task history
├── pages/
│   └── TaskResultPage.tsx    # Per-task result view (polls until complete)
└── services/
    └── api.ts                # All fetch calls — single source of truth for API
```

## API Base URL & Vite Proxy
```typescript
// services/api.ts
const API_BASE_URL = '/api';
```
In **dev**: Vite proxies `/api` → `http://localhost:8000` (configured in `vite.config.ts`).
In **production**: Django serves the built frontend; `/api` hits the same origin — no proxy needed.

**Never hardcode `localhost:8000`** in fetch calls — always use `API_BASE_URL = '/api'`.

## Adding a New API Call
Add a function to `frontend/src/services/api.ts`:
```typescript
export async function myNewCall(payload: MyType): Promise<ResultType> {
  const res = await fetch(`${API_BASE_URL}/myresource/`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  if (!res.ok) throw new Error(await res.text());
  return res.json();
}
```

## Task Polling Pattern
`TaskResultPage.tsx` polls `GET /api/tasks/{id}/` on an interval until `status === 'completed'`:
```typescript
useEffect(() => {
  const interval = setInterval(async () => {
    const task = await getTask(id);
    if (task.status === 'completed') {
      clearInterval(interval);
      setTask(task);
    }
  }, 2000);
  return () => clearInterval(interval);
}, [id]);
```
Match this pattern for any new async operation that returns 202.

## Production Build
`npm run build` outputs to `frontend/dist/`. Django + WhiteNoise serves this directory.
`build.sh` runs `collectstatic` which picks up the built frontend assets.
After changing frontend code, the production build must be committed — Render does **not** run `npm build` automatically unless configured in `build.sh`.
