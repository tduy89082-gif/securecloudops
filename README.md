# SecureCloudOps

Secure & Automated Cloud Infrastructure project for learning Cloud Engineering and Cloud Security.

## Phase 1 — Local MVP

Current stack:
- Python 3.12
- FastAPI
- PostgreSQL 16
- SQLAlchemy 2
- pytest
- Docker / Docker Compose

## Run locally

### Option A: Docker Compose

```bash
docker compose up --build
```

API:
- http://localhost:8000
- Swagger: http://localhost:8000/docs
- Health: http://localhost:8000/health

Run tests inside the API container:

```bash
docker compose exec api pytest
```

Stop:

```bash
docker compose down
```

To remove the database volume as well:

```bash
docker compose down -v
```

### Option B: Local Python

Create a virtual environment and install dependencies:

```bash
python -m venv .venv
# Windows PowerShell:
.venv\Scripts\Activate.ps1
# Linux/macOS:
# source .venv/bin/activate

pip install -r requirements.txt
```

Set a local PostgreSQL connection string in `DATABASE_URL`, then:

```bash
uvicorn app.main:app --reload
pytest
```

## API

### Health
`GET /health`

### Tasks
- `GET /tasks`
- `POST /tasks`
- `GET /tasks/{task_id}`
- `PUT /tasks/{task_id}`
- `DELETE /tasks/{task_id}`

Example:

```json
{
  "title": "Learn IAM least privilege"
}
```

## Project goals

This local application is only the workload. The main learning path will be:

1. Local application
2. Docker
3. AWS networking
4. Terraform
5. ECS + RDS
6. IAM + Secrets Manager + KMS
7. GitHub Actions + OIDC
8. WAF + CloudTrail
9. GuardDuty + Security Hub + Inspector
10. EventBridge + Lambda incident response

## Security rules for this repository

- Never commit passwords, API keys, AWS keys, or tokens.
- Use `.env` for local secrets only.
- Use GitHub OIDC rather than long-lived AWS credentials when CI/CD reaches AWS.
- Keep infrastructure changes in Terraform.
