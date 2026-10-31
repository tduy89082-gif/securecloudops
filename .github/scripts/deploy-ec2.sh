
#!/bin/sh
set -eu

PROJECT="/home/ec2-user/securecloudops"
STAGING="/home/ec2-user/securecloudops.new"
STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="${PROJECT}.backup-${STAMP}"
FAILED="${PROJECT}.failed-${STAMP}"

# Cài Git nếu máy chưa có.
if ! command -v git >/dev/null 2>&1; then
  if command -v dnf >/dev/null 2>&1; then
    dnf install -y git
  elif command -v yum >/dev/null 2>&1; then
    yum install -y git
  else
    echo "Cannot find dnf or yum to install Git."
    exit 1
  fi
fi

# Tải đúng commit mà GitHub Actions đang triển khai.
rm -rf "$STAGING"
git clone https://github.com/tduy89082-gif/securecloudops.git "$STAGING"
git -C "$STAGING" checkout --detach "__DEPLOY_SHA__"

# Ensure Docker Compose CLI plugin is installed.
if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose plugin not found. Installing..."

  case "$(uname -m)" in
    x86_64)
      COMPOSE_ARCH="x86_64"
      ;;
    aarch64|arm64)
      COMPOSE_ARCH="aarch64"
      ;;
    *)
      echo "Unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac

  COMPOSE_VERSION="v5.6.1"
  COMPOSE_ASSET="docker-compose-linux-${COMPOSE_ARCH}"
  COMPOSE_URL="https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}"

  TMP_BIN="$(mktemp)"
  TMP_SUMS="$(mktemp)"

  curl --fail --silent --show-error --location \
    "${COMPOSE_URL}/${COMPOSE_ASSET}" -o "$TMP_BIN"

  curl --fail --silent --show-error --location \
    "${COMPOSE_URL}/checksums.txt" -o "$TMP_SUMS"

  EXPECTED_SHA="$(awk -v n="$COMPOSE_ASSET" \
    '{ f=$2; sub(/^\*/, "", f); if (f==n) print $1 }' "$TMP_SUMS")"

  ACTUAL_SHA="$(sha256sum "$TMP_BIN" | awk '{print $1}')"

  if [ -z "$EXPECTED_SHA" ] || [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]; then
    rm -f "$TMP_BIN" "$TMP_SUMS"
    echo "Docker Compose checksum verification failed." >&2
    exit 1
  fi

  PLUGIN_DIR="/usr/local/lib/docker/cli-plugins"
  install -d "$PLUGIN_DIR"
  install -m 0755 "$TMP_BIN" "$PLUGIN_DIR/docker-compose"
  rm -f "$TMP_BIN" "$TMP_SUMS"
fi

docker compose version


# Ensure Docker Buildx is new enough for Compose builds.
BUILDX_VERSION="v0.38.1"

if ! docker buildx version 2>/dev/null | grep -q "$BUILDX_VERSION"; then
  case "$(uname -m)" in
    x86_64)
      BUILDX_ARCH="amd64"
      BUILDX_SHA256="e25d5cd675092bb5d1d03632fdc46cdf3fede7b514dc5f023a105e00d3ce5ad4"
      ;;
    aarch64|arm64)
      BUILDX_ARCH="arm64"
      BUILDX_SHA256="3b83b3731916ba433feccaaa689fe5bcdc81c641d92c8e6c2ea865dfa141c97a"
      ;;
    *)
      echo "Unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac

  BUILDX_URL="https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.linux-${BUILDX_ARCH}"
  TMP_BIN="$(mktemp)"

  curl --fail --silent --show-error --location \
    "$BUILDX_URL" -o "$TMP_BIN"

  printf '%s  %s\n' "$BUILDX_SHA256" "$TMP_BIN" | sha256sum -c -

  install -d /usr/local/lib/docker/cli-plugins
  install -m 0755 "$TMP_BIN" \
    /usr/local/lib/docker/cli-plugins/docker-buildx
  rm -f "$TMP_BIN"
fi

docker buildx version


# Fetch the database password from Parameter Store.
POSTGRES_PASSWORD="$(aws ssm get-parameter \
  --name "/securecloudops/dev/database/password" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text \
  --region ap-southeast-2)"

if [ -z "$POSTGRES_PASSWORD" ] || [ "$POSTGRES_PASSWORD" = "None" ]; then
  echo "Database password was not returned by Parameter Store." >&2
  exit 1
fi

export POSTGRES_PASSWORD

# Fetch the CloudFront origin verification token from Parameter Store.
ORIGIN_VERIFY_TOKEN="$(aws ssm get-parameter \
  --name "/securecloudops/dev/cloudfront/origin-verify-token" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text \
  --region ap-southeast-2)"

if [ -z "$ORIGIN_VERIFY_TOKEN" ] || [ "$ORIGIN_VERIFY_TOKEN" = "None" ]; then
  echo "CloudFront origin verification token was not returned." >&2
  exit 1
fi

export ORIGIN_VERIFY_TOKEN

# URL-encode the password before constructing the database URL.
ENCODED_PASSWORD="$(python3 -c \
  'import os; from urllib.parse import quote; print(quote(os.environ["POSTGRES_PASSWORD"], safe=""))')"

export DATABASE_URL="postgresql+psycopg://app_user:${ENCODED_PASSWORD}@db:5432/securecloudops"
unset ENCODED_PASSWORD


# Giữ bản source hiện tại để có thể phục hồi.
if [ -d "$PROJECT" ]; then
  mv "$PROJECT" "$BACKUP"
fi

mv "$STAGING" "$PROJECT"
chown -R ec2-user:ec2-user "$PROJECT"

cd "$PROJECT"

if ! docker compose up -d --build --remove-orphans; then
  echo "Docker Compose failed. Restoring previous source."
  cd /
  mv "$PROJECT" "$FAILED"

  if [ -d "$BACKUP" ]; then
    mv "$BACKUP" "$PROJECT"
    (cd "$PROJECT" && docker compose up -d --build) || true
  fi

  exit 1
fi

# Kiểm tra API trong tối đa khoảng 60 giây.
attempt=0
while [ "$attempt" -lt 30 ]; do
  if python3 - <<'PY'
import os
import urllib.request

token = os.environ.get("ORIGIN_VERIFY_TOKEN", "")

if not token:
    raise SystemExit("Origin verification token is missing.")

request = urllib.request.Request(
    "http://127.0.0.1:8000/health",
    headers={
        "X-SecureCloudOps-Origin-Verify": token
    }
)

with urllib.request.urlopen(request, timeout=5) as response:
    print(response.read().decode("utf-8"))

    if response.status != 200:
        raise SystemExit("API health check failed.")
PY
then
    echo
    docker compose ps
    exit 0
fi
  attempt=$((attempt + 1))
  sleep 2
done

echo "Health check failed. Showing application logs:"
docker compose logs --tail=80 api db || true

# Phục hồi source cũ nếu health check thất bại.
cd /
mv "$PROJECT" "$FAILED"

if [ -d "$BACKUP" ]; then
  mv "$BACKUP" "$PROJECT"
  (cd "$PROJECT" && docker compose up -d --build) || true
fi

exit 1
