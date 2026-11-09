# Klasify backend deployment (HTTPS)

Release builds of the Flutter app are HTTPS-only (cleartext HTTP is disabled
in the release manifest), so a real deployment needs an HTTPS endpoint in
front of the Node/Express API.

## Option A — reverse proxy in front of Docker (recommended)

1. Run the backend as documented in `backend/README.md`:
   ```
   cd backend
   docker compose up -d
   ```
   The API listens on `http://127.0.0.1:8080` on the host (container port 80,
   published as 8080 by `backend/docker-compose.yml`).

2. Put a TLS-terminating reverse proxy in front of it. Any of these work:
   - **Caddy** (automatic Let's Encrypt):
     ```
     api.klasify.app {
       reverse_proxy 127.0.0.1:8080
     }
     ```
   - **nginx** with a cert from certbot:
     ```
     server {
       listen 443 ssl;
       server_name api.klasify.app;
       ssl_certificate     /etc/letsencrypt/live/api.klasify.app/fullchain.pem;
       ssl_certificate_key /etc/letsencrypt/live/api.klasify.app/privkey.pem;
       location / { proxy_pass http://127.0.0.1:8080; }
     }
     ```
   - A cloud load balancer (AWS ALB, GCP HTTPS LB, Cloudflare) terminating
     TLS and forwarding to the container port 8080.

3. Point DNS `api.klasify.app` at the host. Verify:
   ```
   curl https://api.klasify.app/auth/login -X POST -H 'Content-Type: application/json' -d '{}'
   ```
   (expect `422 VALIDATION_ERROR`, not a connection error).

## Option B — managed Node host

Deploy `backend/` to a host that provides HTTPS by default (Render, Railway,
Fly.io, Heroku). Set the env vars from `backend/docker-compose.yml`
(`KLASIFY_DB_HOST`, `KLASIFY_DB_PORT`, `KLASIFY_DB_NAME`, `KLASIFY_DB_USER`,
`KLASIFY_DB_PASS`, `KLASIFY_JWT_SECRET`, `GOOGLE_CLIENT_ID`) in the host's
dashboard. The MySQL volume must be a managed database, not the container's.

## Option C — free tunnel, no domain purchase

For a zero-cost demo endpoint, Cloudflare Quick Tunnel gives an HTTPS URL
with no account or domain:

    cloudflared tunnel --url http://localhost:8080

Point `KLASIFY_API_URL` at the printed `https://<random>.trycloudflare.com`
URL. The URL changes every time the tunnel restarts, so use it for a demo
build, not for a long-lived release. A named Cloudflare Tunnel (also free)
fixes the URL once a domain is available; Render/Fly/Railway free subdomains
are the alternative when the API can move off this machine.

## Building the release APK

Once the HTTPS endpoint exists:

```
flutter build apk --release \
  --dart-define=KLASIFY_API_URL=https://api.klasify.app \
  --dart-define=GOOGLE_WEB_CLIENT_ID=<your-web-client-id>
```

The release manifest is HTTPS-only, so a release build pointed at
`http://...` will fail at runtime with a cleartext-not-permitted error.
Debug/profile builds keep cleartext enabled for local dev against
`http://192.168.1.67:8080`.

## Checklist before shipping

- [ ] `GOOGLE_CLIENT_ID` set on the API host (Google Sign-In returns
      `VALIDATION_ERROR` otherwise).
- [ ] `KLASIFY_JWT_SECRET` changed from the dev default to a long random string.
- [ ] MySQL reachable from the API host (managed DB or same VPC).
- [ ] HTTPS endpoint verified with curl.
- [ ] APK built with `--dart-define=KLASIFY_API_URL=https://...`.
- [ ] Android OAuth client ID registered with the **release** signing
      certificate's SHA-1 (the debug SHA-1 `93:7D:...` is for debug builds only).