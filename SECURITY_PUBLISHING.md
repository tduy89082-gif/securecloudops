# Publishing and secret-handling checklist

- Keep `.env`, access-key CSV exports, private keys, AWS profiles, Terraform state and local toolchains outside Git.
- The repository ignore rules exclude `/CLI/`, credentials, `.env`, `.pem`, Terraform state and local account-specific Phase 10 JSON payloads.
- A file being ignored does not remove it from a previous Git commit. If a credential was ever committed, rotate it and clean Git history before publishing.
- Never put a real DB password or CloudFront origin token in `docker-compose.yml`, GitHub workflow YAML, test fixtures or screenshots.
- Prefer GitHub Actions OIDC and IAM roles rather than long-lived AWS access keys.
- Before `git add`, inspect `git status --short` and `git diff --cached --name-only`.
