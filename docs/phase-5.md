## Deployment verification

- [x] API container running on EC2
- [x] PostgreSQL container healthy
- [x] GET /health returns status: ok from Windows
- [x] POST /tasks returns HTTP 201
- [x] GET /tasks/1 returns HTTP 200
- [ ] GET /tasks lists tasks successfully
- [ ] PUT /tasks/{task_id} updates a task
- [ ] DELETE /tasks/{task_id} removes a task

## Security notes

- Restrict SSH port 22 to the developer's public IP.
- Restrict API port 8000 to the developer's public IP for this demo.
- Do not expose PostgreSQL port 5432 publicly.
- IMDSv2 is required on the EC2 instance.
- The demo currently uses HTTP, not HTTPS.