# Phase 1 — Local MVP

## Objective

Build a small application that is deterministic, testable, and containerized before introducing AWS.

## Definition of Done

- [x] FastAPI API starts
- [x] PostgreSQL runs in Docker
- [x] API connects to PostgreSQL
- [x] CRUD task endpoints exist
- [x] Health endpoint exists
- [x] pytest is configured
- [x] GitHub Actions runs tests
- [ ] Add database migrations
- [ ] Add application authentication
- [ ] Add structured logging
- [ ] Add security scanning
- [ ] Deploy to AWS

## Why this order?

The cloud infrastructure will be much easier to reason about if the workload is already reproducible locally. This also gives us a stable baseline for later security experiments.
