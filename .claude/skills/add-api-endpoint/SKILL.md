---
name: add-api-endpoint
description: Add a REST endpoint to UniSave — URL conventions, DRF viewset pattern, 202 for async, serializer wiring
---

# Add API Endpoint

## Existing Endpoints (`core/urls.py`)
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

## URL Convention
- All endpoints under `/api/` prefix.
- Use plural resource names: `/api/subjects/`, `/api/materials/`, `/api/tasks/`.
- Detail endpoints: `/api/<resource>/{id}/`.
- Vite proxies `/api` → `http://localhost:8000` in dev — no CORS issues during development.

## DRF Viewset Pattern
UniSave uses class-based `APIView` or `ModelViewSet`. Follow the existing pattern in `core/views.py`:

```python
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status

class MyResourceListView(APIView):
    def get(self, request):
        qs = MyModel.objects.all()
        serializer = MyModelSerializer(qs, many=True)
        return Response(serializer.data)

    def post(self, request):
        serializer = MyModelSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        obj = serializer.save()
        return Response(MyModelSerializer(obj).data, status=status.HTTP_201_CREATED)
```

## 202 for Async Operations
Task creation returns **202 Accepted** (not 201) because the pipeline runs in a background thread:
```python
return Response(serializer.data, status=status.HTTP_202_ACCEPTED)
```
Use 202 for any endpoint that starts background work and the result isn't immediately available.

## Wiring a New Endpoint
1. Add serializer to `core/serializers.py`
2. Add view class to `core/views.py`
3. Add URL to `core/urls.py`:
```python
path('api/myresource/', views.MyResourceListView.as_view()),
path('api/myresource/<int:pk>/', views.MyResourceDetailView.as_view()),
```
4. The frontend calls via `frontend/src/services/api.ts` — add a fetch function there to match.

## Serializer Notes
- Nested serializers (e.g. `TaskResult` inside `TaskQuestion` inside `ExamTask`) use `many=True` and are defined as fields on the parent serializer.
- `read_only=True` on computed or auto fields (`created_at`, `status` set by the pipeline).
- `JSONField` content (e.g. `quotes`, `embedding`) serializes automatically — no special handling needed.
