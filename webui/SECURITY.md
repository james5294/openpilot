# Security Guide for Fork Swap WebUI

## TLS/HTTPS Requirement

**⚠️ WARNING**: The Fork Swap WebUI server does NOT provide TLS encryption natively.

### Production Deployment

For any deployment exposed beyond localhost, you MUST run behind a TLS-terminating reverse proxy.

#### Option 1: Nginx

```nginx
server {
    listen 443 ssl;
    server_name forkswap.yourdomain.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://127.0.0.1:8888;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

#### Option 2: Caddy

```caddyfile
forkswap.yourdomain.com {
    reverse_proxy localhost:8888
}
```

Caddy automatically obtains and renews TLS certificates.

#### Option 3: SSH Tunnel (Development)

```bash
# On your local machine
ssh -L 8888:localhost:8888 comma@device-ip
# Then access http://localhost:8888
```

### Environment Configuration

When using a local reverse proxy:

```bash
# Bind only to localhost (proxy handles external traffic)
export FORKSWAP_BIND_ALL=0
```

---

## Authentication

### Enabling Token Authentication

Set a strong random token:

```bash
# Via environment variable
export FORKSWAP_AUTH_TOKEN="$(openssl rand -hex 32)"

# Or in config.json
{
  "webui": {
    "auth_token": "your-64-char-hex-token-here"
  }
}
```

### Using Authentication

Include the token in API requests:

```bash
curl -H "Authorization: Bearer YOUR_TOKEN" http://localhost:8888/api/status
```

### Token Security

- Use `openssl rand -hex 32` or similar for token generation
- Token comparison uses `hmac.compare_digest` (timing-safe)
- Never commit tokens to version control

---

## Rate Limiting

The server implements per-IP rate limiting:

| Setting | Default | Purpose |
|---------|---------|---------|
| `RATE_LIMIT_REQUESTS` | 60 | Max requests per IP per window |
| `RATE_LIMIT_WINDOW_SECONDS` | 60 | Time window in seconds |

Rate-limited requests receive HTTP 429 (Too Many Requests).

---

## Input Validation

All user inputs are validated:

### Fork Names
- Alphanumeric, dashes, underscores only
- Max 64 characters
- Must start with alphanumeric
- Rejects: `../`, `;`, `|`, `$()`, backticks

### Git URLs
- HTTPS or SSH protocols only
- Must end with `.git`
- Rejects: `file://`, command injection

### Branch Names
- Alphanumeric, dashes, underscores, forward slashes
- Max 100 characters
- Rejects: `..`, shell metacharacters

### Commands
- Strict allowlist: `switch`, `update`, `list`, `status`, `clone`, `delete`
- All other commands rejected

---

## Security Headers

The server sets these security headers:

| Header | Value | Purpose |
|--------|-------|---------|
| `X-Content-Type-Options` | `nosniff` | Prevent MIME sniffing |
| `X-Frame-Options` | `DENY` | Prevent clickjacking |
| `X-XSS-Protection` | `1; mode=block` | XSS filter |
| `Content-Security-Policy` | See below | Content restrictions |

### CSP Policy

```
default-src 'self';
script-src 'self' 'unsafe-inline';
style-src 'self' 'unsafe-inline';
font-src 'self' https://fonts.googleapis.com https://fonts.gstatic.com;
frame-ancestors 'none';
base-uri 'self'
```

---

## Reporting Security Issues

If you discover a security vulnerability:

1. **Do NOT** open a public GitHub issue
2. Email security concerns privately
3. Include steps to reproduce
4. Allow time for a fix before disclosure

---

## Security Checklist

### Before Production Deployment

- [ ] TLS proxy configured (nginx/caddy)
- [ ] `FORKSWAP_AUTH_TOKEN` set to strong random value
- [ ] `FORKSWAP_BIND_ALL=0` if using local proxy
- [ ] Firewall rules restrict port 8888 to proxy only
- [ ] Log monitoring configured
- [ ] Rate limit thresholds appropriate for expected load

### Ongoing

- [ ] Monitor `/api/health` endpoint
- [ ] Review activity logs for anomalies
- [ ] Keep server.py updated
- [ ] Rotate auth tokens periodically
