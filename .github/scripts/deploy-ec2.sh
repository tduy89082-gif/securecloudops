
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
  if curl -fsS http://127.0.0.1:8000/health; then
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
