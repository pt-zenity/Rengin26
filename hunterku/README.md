# hunterku.xyz — reNgine-ng 3.0.0 (Celery Snapshot)

Deployment reNgine-ng 3.0.0 dengan domain **hunterku.xyz**, dibangun di atas
[Security-Tools-Alliance/rengine-ng](https://github.com/Security-Tools-Alliance/rengine-ng)
pinned commit `205d3ffd0edc32db60b3954d93d11d6affdfbc2d`.

## Docker Hub

Semua images tersedia di: **[harispyn/hunterku](https://hub.docker.com/r/harispyn/hunterku/tags)**

| Tag | Komponen | Ukuran |
|-----|----------|--------|
| `web-v3.0.0` / `web-latest` | Django + ASGI (reNgine web app) | ~2.84 GB |
| `celery-v3.0.0` / `celery-latest` | Celery worker + security tools | ~7.2 GB |
| `proxy-v3.0.0` / `proxy-latest` | Nginx reverse proxy (SSL) | ~66 MB |
| `postgres-v3.0.0` / `postgres-latest` | PostgreSQL database | ~770 MB |
| `redis-v3.0.0` / `redis-latest` | Redis broker | ~60 MB |
| `ollama-v3.0.0` / `ollama-latest` | Ollama AI engine | ~1.37 GB |

## Instalasi Cepat

```bash
# Clone installer
git clone https://github.com/pt-zenity/Rengin26.git
cd Rengin26

# Jalankan installer
sudo bash rengine-ng-3.0.0-celery.sh \
  --domain hunterku.xyz \
  --username admin \
  --email admin@hunterku.xyz \
  --password 'PASSWORD_KUAT_ANDA' \
  --min-concurrency 5 \
  --max-concurrency 20
```

## Akses Aplikasi

```
https://hunterku.xyz
```

> **Catatan**: Tambahkan DNS record atau entry `/etc/hosts`:
> ```
> <IP_SERVER>  hunterku.xyz www.hunterku.xyz
> ```

## Konfigurasi Domain (hunterku.xyz)

### File yang Diubah

| File | Perubahan |
|------|-----------|
| `config/.env` | `DOMAIN_NAME=hunterku.xyz`, `TRUST_PROXY_HEADERS=True` |
| `config/rengine.conf` | `server_name hunterku.xyz www.hunterku.xyz ...` |
| `certs/rengine.pem` | SSL cert baru CN=`hunterku.xyz` (valid 10 tahun) |
| `web/settings.py` | CSRF fix: `CSRF_TRUSTED_ORIGINS`, `CSRF_COOKIE_SECURE=False`, `CSRF_USE_SESSIONS=False` |

### Struktur File
```
hunterku/
├── README.md                      # Dokumentasi ini
├── README_original.md             # README asli dari Rengin26
├── rengine-ng-3.0.0-celery.sh     # Script installer
├── config/
│   ├── .env                       # Environment variables (domain, DB, dsb)
│   └── rengine.conf               # Nginx proxy config
├── certs/
│   ├── rengine.pem                # SSL certificate untuk hunterku.xyz
│   └── rengine_chain.pem          # Certificate chain (CA)
└── web/
    └── settings.py                # Django settings dengan CSRF fix (copy dari production)
```

## Credentials Default

| Parameter | Value |
|-----------|-------|
| URL | `https://hunterku.xyz` |
| Username | `admin` |
| Password | `AdminPass123!` |
| Email | `admin@hunterku.xyz` |

> **PENTING**: Ganti password setelah login pertama!

## Perbaikan CSRF (403 Forbidden)

### Masalah
- Django menolak request POST dengan error `403 CSRF verification failed`
- Penyebab: nginx reverse proxy meneruskan `X-Forwarded-Proto: https` namun Django tidak mempercayainya

### Solusi
1. **`.env`** — Tambahkan `TRUST_PROXY_HEADERS=True`
2. **`settings.py`** — Update konfigurasi CSRF:
   ```python
   CSRF_TRUSTED_ORIGINS = [
       f"https://{DOMAIN_NAME}",
       f"http://{DOMAIN_NAME}",
       "https://localhost", "http://localhost",
       "https://127.0.0.1", "http://127.0.0.1",
   ]
   CSRF_COOKIE_SECURE = False    # Kompatibel dengan nginx proxy
   CSRF_COOKIE_HTTPONLY = False  # Wajib untuk non-session CSRF
   CSRF_USE_SESSIONS = False     # Cookie-based (lebih kompatibel)
   ```
3. **Force-recreate container** (bukan hanya restart):
   ```bash
   cd /opt/rengine-ng-celery-3.0.0
   RENGINE_VERSION=$(cat web/reNgine/version.txt) \
   docker compose -f docker/docker-compose.yml up -d --force-recreate web
   ```

## Tools Reconnaissance Terinstal

| Tool | Fungsi |
|------|--------|
| nuclei | Vulnerability scanner |
| httpx | HTTP probing |
| naabu | Port scanner |
| dnsx | DNS resolver |
| subfinder | Subdomain discovery |
| theHarvester | OSINT gathering |
| wafw00f | WAF detection |
| amass | Attack surface mapping |
| gau | URL gathering |
| nmap | Network scanner |
| CMSeek | CMS detection |

## Commands Berguna

```bash
# Status container
docker compose -f docker/docker-compose.yml ps

# Lihat log Celery
docker logs -f rengine-celery-1

# Lihat log Beat
docker logs -f rengine-celery-beat-1

# Cek Celery worker status
docker exec rengine-celery-1 \
  poetry -C /home/rengine/rengine run celery -A reNgine status

# Restart proxy (setelah ganti domain/cert)
docker restart rengine-proxy-1
```

## Spesifikasi

- **reNgine-ng version**: 3.0.0
- **Pinned commit**: `205d3ffd0edc32db60b3954d93d11d6affdfbc2d`
- **Domain**: `hunterku.xyz`
- **Docker Hub**: `harispyn/hunterku`
- **Base OS**: Ubuntu 24.04 / Debian 12+
- **Celery concurrency**: 5–20 workers
