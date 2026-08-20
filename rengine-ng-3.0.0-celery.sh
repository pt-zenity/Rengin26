#!/usr/bin/env bash
set -Eeuo pipefail

# ==============================================================================
# reNgine-ng 3.0.0 "Celery transition snapshot" installer
# Pinned commit: 205d3ffd0edc32db60b3954d93d11d6affdfbc2d
#
# Target OS : Ubuntu 22.04/24.04, Debian 12+
# Installs   : Docker Engine + Compose plugin (if missing), git, make, curl, etc.
# Deploys    : reNgine-ng 3.0.0 from source with Celery + Celery Beat
#
# Usage:
#   sudo bash rengine-ng-3.0.0-celery.sh
#
# Optional:
#   sudo bash rengine-ng-3.0.0-celery.sh \
#     --domain rengine.example.com \
#     --username admin \
#     --email admin@example.com \
#     --password 'StrongPasswordHere' \
#     --min-concurrency 5 \
#     --max-concurrency 20
#
# Environment overrides:
#   RENGINE_DIR=/opt/rengine-ng-celery
#   RENGINE_DOMAIN=rengine.example.com
#   RENGINE_ADMIN_USER=admin
#   RENGINE_ADMIN_EMAIL=admin@example.com
#   RENGINE_ADMIN_PASSWORD=...
#   MIN_CONCURRENCY=5
#   MAX_CONCURRENCY=20
# ==============================================================================

REPO_URL="https://github.com/Security-Tools-Alliance/rengine-ng.git"
PINNED_COMMIT="205d3ffd0edc32db60b3954d93d11d6affdfbc2d"
EXPECTED_VERSION="3.0.0"

RENGINE_DIR="${RENGINE_DIR:-/opt/rengine-ng-celery-3.0.0}"
RENGINE_DOMAIN="${RENGINE_DOMAIN:-rengine.local}"
RENGINE_ADMIN_USER="${RENGINE_ADMIN_USER:-admin}"
RENGINE_ADMIN_EMAIL="${RENGINE_ADMIN_EMAIL:-admin@localhost}"
RENGINE_ADMIN_PASSWORD="${RENGINE_ADMIN_PASSWORD:-}"
MIN_CONCURRENCY="${MIN_CONCURRENCY:-5}"
MAX_CONCURRENCY="${MAX_CONCURRENCY:-20}"
SKIP_DOCKER_INSTALL=0
NO_START=0

C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[1;33m'
C_CYAN='\033[0;36m'

log()  { printf "%b[+]%b %s\n" "$C_GREEN" "$C_RESET" "$*"; }
info() { printf "%b[i]%b %s\n" "$C_CYAN" "$C_RESET" "$*"; }
warn() { printf "%b[!]%b %s\n" "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf "%b[x]%b %s\n" "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

trap 'die "Installer gagal pada baris $LINENO. Cek output/log di atas."' ERR

usage() {
  cat <<'EOF'
reNgine-ng 3.0.0 Celery snapshot installer

Options:
  --domain DOMAIN             Domain/hostname untuk reNgine
  --username USER             Django superuser username
  --email EMAIL               Django superuser email
  --password PASS             Django superuser password
  --dir PATH                  Lokasi instalasi (default /opt/rengine-ng-celery-3.0.0)
  --min-concurrency N         Celery minimum concurrency (minimum 5)
  --max-concurrency N         Celery maximum concurrency
  --skip-docker-install       Jangan install Docker otomatis
  --no-start                  Build/configure saja, jangan start container
  -h, --help                  Tampilkan bantuan
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) RENGINE_DOMAIN="${2:?Missing value}"; shift 2 ;;
    --username) RENGINE_ADMIN_USER="${2:?Missing value}"; shift 2 ;;
    --email) RENGINE_ADMIN_EMAIL="${2:?Missing value}"; shift 2 ;;
    --password) RENGINE_ADMIN_PASSWORD="${2:?Missing value}"; shift 2 ;;
    --dir) RENGINE_DIR="${2:?Missing value}"; shift 2 ;;
    --min-concurrency) MIN_CONCURRENCY="${2:?Missing value}"; shift 2 ;;
    --max-concurrency) MAX_CONCURRENCY="${2:?Missing value}"; shift 2 ;;
    --skip-docker-install) SKIP_DOCKER_INSTALL=1; shift ;;
    --no-start) NO_START=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Argumen tidak dikenal: $1" ;;
  esac
done

[[ $EUID -eq 0 ]] || die "Jalankan sebagai root: sudo bash $0"

[[ "$MIN_CONCURRENCY" =~ ^[0-9]+$ ]] || die "MIN_CONCURRENCY harus angka."
[[ "$MAX_CONCURRENCY" =~ ^[0-9]+$ ]] || die "MAX_CONCURRENCY harus angka."
(( MIN_CONCURRENCY >= 5 )) || die "Snapshot ini merekomendasikan MIN_CONCURRENCY minimal 5."
(( MAX_CONCURRENCY >= MIN_CONCURRENCY )) || die "MAX_CONCURRENCY harus >= MIN_CONCURRENCY."

if [[ -z "$RENGINE_ADMIN_PASSWORD" ]]; then
  if command -v openssl >/dev/null 2>&1; then
    RENGINE_ADMIN_PASSWORD="$(openssl rand -hex 18)"
  else
    RENGINE_ADMIN_PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
  fi
  GENERATED_PASSWORD=1
else
  GENERATED_PASSWORD=0
fi

detect_os() {
  [[ -f /etc/os-release ]] || die "/etc/os-release tidak ditemukan."
  # shellcheck disable=SC1091
  source /etc/os-release
  case "${ID:-}" in
    ubuntu|debian) ;;
    *) die "Installer otomatis ini mendukung Ubuntu/Debian. OS terdeteksi: ${ID:-unknown}" ;;
  esac
  OS_ID="$ID"
  OS_CODENAME="${VERSION_CODENAME:-}"
  [[ -n "$OS_CODENAME" ]] || die "Tidak dapat menentukan VERSION_CODENAME."
}

install_base_packages() {
  log "Memasang dependency dasar..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y \
    ca-certificates curl gnupg git make openssl jq \
    lsb-release coreutils sed grep gawk iproute2
}

install_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    log "Docker + Docker Compose plugin sudah tersedia."
    return
  fi

  (( SKIP_DOCKER_INSTALL == 0 )) || die "Docker/Compose tidak ditemukan dan --skip-docker-install digunakan."

  log "Memasang Docker Engine dari repository resmi Docker..."

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  ARCH="$(dpkg --print-architecture)"
  cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS_ID} ${OS_CODENAME} stable
EOF

  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

  systemctl enable --now docker
}

verify_docker() {
  docker version >/dev/null
  docker compose version >/dev/null
  log "Docker: $(docker --version)"
  log "Compose: $(docker compose version --short 2>/dev/null || docker compose version)"
}

clone_snapshot() {
  if [[ -d "$RENGINE_DIR/.git" ]]; then
    warn "Repository sudah ada: $RENGINE_DIR"
    git -C "$RENGINE_DIR" remote set-url origin "$REPO_URL"
    git -C "$RENGINE_DIR" fetch --all --tags --prune
  else
    if [[ -e "$RENGINE_DIR" ]]; then
      die "$RENGINE_DIR sudah ada tetapi bukan Git repository."
    fi
    mkdir -p "$(dirname "$RENGINE_DIR")"
    git clone "$REPO_URL" "$RENGINE_DIR"
  fi

  log "Checkout snapshot Celery: $PINNED_COMMIT"
  git -C "$RENGINE_DIR" checkout --detach "$PINNED_COMMIT"

  ACTUAL_COMMIT="$(git -C "$RENGINE_DIR" rev-parse HEAD)"
  [[ "$ACTUAL_COMMIT" == "$PINNED_COMMIT" ]] \
    || die "Commit salah. Expected=$PINNED_COMMIT Actual=$ACTUAL_COMMIT"

  VERSION="$(tr -d '[:space:]' < "$RENGINE_DIR/web/reNgine/version.txt")"
  [[ "$VERSION" == "$EXPECTED_VERSION" ]] \
    || die "Versi salah. Expected=$EXPECTED_VERSION Actual=$VERSION"

  log "Commit terverifikasi: $ACTUAL_COMMIT"
  log "Versi terverifikasi: $VERSION"
}

verify_legacy_celery_files() {
  local required=(
    "docker/celery/Dockerfile"
    "docker/celery/entrypoint.sh"
    "docker/beat/entrypoint.sh"
    "docker/docker-compose.yml"
    "docker/docker-compose.build.yml"
    ".env-dist"
    "install.sh"
    "Makefile"
  )

  for file in "${required[@]}"; do
    [[ -f "$RENGINE_DIR/$file" ]] || die "File wajib tidak ditemukan: $file"
  done

  grep -qE '^[[:space:]]*celery:' "$RENGINE_DIR/docker/docker-compose.yml" \
    || die "Service celery tidak ditemukan di docker-compose.yml"
  grep -qE '^[[:space:]]*celery-beat:' "$RENGINE_DIR/docker/docker-compose.yml" \
    || die "Service celery-beat tidak ditemukan di docker-compose.yml"
  grep -q 'django_celery_beat.schedulers:DatabaseScheduler' "$RENGINE_DIR/docker/beat/entrypoint.sh" \
    || die "DatabaseScheduler Celery Beat tidak ditemukan."

  log "Celery worker + Celery Beat legacy terverifikasi."
}

set_env_value() {
  local file="$1" key="$2" value="$3" tmp
  tmp="$(mktemp)"
  awk -v k="$key" -v v="$value" '
    BEGIN { found=0 }
    $0 ~ "^" k "=" {
      print k "=" v
      found=1
      next
    }
    { print }
    END {
      if (!found) print k "=" v
    }
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

configure_env() {
  cd "$RENGINE_DIR"

  if [[ ! -f .env ]]; then
    cp .env-dist .env
  else
    cp .env ".env.backup.$(date +%Y%m%d-%H%M%S)"
  fi

  # Always pin build-from-source so the historical code and image match.
  set_env_value .env "INSTALL_TYPE" "source"
  set_env_value .env "DOMAIN_NAME" "$RENGINE_DOMAIN"
  set_env_value .env "DJANGO_SUPERUSER_USERNAME" "$RENGINE_ADMIN_USER"
  set_env_value .env "DJANGO_SUPERUSER_EMAIL" "$RENGINE_ADMIN_EMAIL"
  set_env_value .env "DJANGO_SUPERUSER_PASSWORD" "$RENGINE_ADMIN_PASSWORD"
  set_env_value .env "MIN_CONCURRENCY" "$MIN_CONCURRENCY"
  set_env_value .env "MAX_CONCURRENCY" "$MAX_CONCURRENCY"

  chmod 600 .env

  log ".env dikonfigurasi:"
  info "DOMAIN_NAME=$RENGINE_DOMAIN"
  info "INSTALL_TYPE=source"
  info "MIN_CONCURRENCY=$MIN_CONCURRENCY"
  info "MAX_CONCURRENCY=$MAX_CONCURRENCY"
}

free_required_ports_note() {
  if ss -lnt '( sport = :443 or sport = :8082 )' 2>/dev/null | grep -q LISTEN; then
    warn "Port 443 dan/atau 8082 sedang digunakan. reNgine proxy memakai port tersebut."
    ss -lntp '( sport = :443 or sport = :8082 )' || true
  fi
}

build_and_install() {
  cd "$RENGINE_DIR"
  chmod +x install.sh
  log "Menjalankan installer upstream snapshot dalam mode non-interaktif/source..."
  INSTALL_TYPE=source ./install.sh -n
}

compose_cmd() {
  (
    cd "$RENGINE_DIR"
    docker compose \
      -f docker/docker-compose.yml \
      -f docker/docker-compose.build.yml \
      "$@"
  )
}

wait_for_container() {
  local name="$1" max="${2:-180}" i status health
  for ((i=1; i<=max; i++)); do
    status="$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null || true)"
    health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$name" 2>/dev/null || true)"
    if [[ "$status" == "running" && ( "$health" == "healthy" || "$health" == "none" ) ]]; then
      return 0
    fi
    if [[ "$status" == "exited" || "$status" == "dead" ]]; then
      return 1
    fi
    sleep 2
  done
  return 1
}

verify_runtime() {
  log "Memeriksa container..."
  compose_cmd ps || true

  local failed=0
  for c in rengine-db-1 rengine-redis-1 rengine-celery-1 rengine-celery-beat-1 rengine-web-1 rengine-proxy-1; do
    if wait_for_container "$c" 180; then
      log "$c berjalan."
    else
      warn "$c belum healthy/running."
      docker logs --tail 80 "$c" 2>&1 || true
      failed=1
    fi
  done

  log "Verifikasi Celery worker..."
  if docker exec rengine-celery-1 \
      poetry -C /home/rengine/rengine run \
      celery -A reNgine status; then
    log "Celery worker merespons."
  else
    warn "Celery status gagal."
    failed=1
  fi

  log "Verifikasi registered Celery tasks..."
  docker exec rengine-celery-1 \
    poetry -C /home/rengine/rengine run \
    celery -A reNgine inspect registered 2>/dev/null | head -n 80 || true

  log "Verifikasi Celery Beat process..."
  if docker exec rengine-celery-beat-1 sh -lc \
      'ps aux | grep -v grep | grep -q "[c]elery.*beat"'; then
    log "Celery Beat aktif."
  else
    warn "Process Celery Beat tidak terdeteksi."
    docker logs --tail 100 rengine-celery-beat-1 2>&1 || true
    failed=1
  fi

  log "Redis ping..."
  docker exec rengine-redis-1 redis-cli ping || {
    warn "Redis PING gagal."
    failed=1
  }

  if (( failed != 0 )); then
    warn "Instalasi selesai tetapi ada komponen yang perlu diperiksa."
    info "Celery log: docker logs -f rengine-celery-1"
    info "Beat log  : docker logs -f rengine-celery-beat-1"
    return 1
  fi

  log "Semua pemeriksaan utama berhasil."
}

save_credentials() {
  local cred="/root/rengine-ng-celery-3.0.0-credentials.txt"
  cat >"$cred" <<EOF
reNgine-ng 3.0.0 Celery transition snapshot
Commit: $PINNED_COMMIT
Install directory: $RENGINE_DIR
Domain: $RENGINE_DOMAIN
Username: $RENGINE_ADMIN_USER
Email: $RENGINE_ADMIN_EMAIL
Password: $RENGINE_ADMIN_PASSWORD
EOF
  chmod 600 "$cred"
  info "Credential tersimpan root-only: $cred"
}

print_summary() {
  cat <<EOF

==============================================================================
 reNgine-ng 3.0.0 Celery snapshot
==============================================================================
 Commit       : $PINNED_COMMIT
 Directory    : $RENGINE_DIR
 Domain       : $RENGINE_DOMAIN
 Admin        : $RENGINE_ADMIN_USER
 Celery       : rengine-celery-1
 Celery Beat  : rengine-celery-beat-1
 Concurrency  : $MIN_CONCURRENCY .. $MAX_CONCURRENCY

 Useful commands:
   cd "$RENGINE_DIR"
   docker compose -f docker/docker-compose.yml -f docker/docker-compose.build.yml ps
   docker logs -f rengine-celery-1
   docker logs -f rengine-celery-beat-1

   docker exec -it rengine-celery-1 \
     poetry -C /home/rengine/rengine run celery -A reNgine status

   docker exec -it rengine-celery-1 \
     poetry -C /home/rengine/rengine run celery -A reNgine inspect active

   docker exec -it rengine-celery-1 \
     poetry -C /home/rengine/rengine run celery -A reNgine inspect scheduled

 IMPORTANT:
   Repository dipin ke detached commit. Jangan 'git pull' jika ingin mempertahankan
   versi transisi Celery ini.
==============================================================================
EOF

  if (( GENERATED_PASSWORD == 1 )); then
    printf "%bGenerated admin password:%b %s\n" "$C_YELLOW" "$C_RESET" "$RENGINE_ADMIN_PASSWORD"
  fi
}

main() {
  detect_os
  install_base_packages
  install_docker
  verify_docker
  clone_snapshot
  verify_legacy_celery_files
  configure_env
  free_required_ports_note
  save_credentials

  if (( NO_START == 1 )); then
    warn "--no-start aktif: installer upstream tidak dijalankan."
    print_summary
    exit 0
  fi

  build_and_install

  # Upstream installer already starts services. Verify the resulting stack.
  if ! verify_runtime; then
    print_summary
    exit 2
  fi

  print_summary
}

main "$@"
