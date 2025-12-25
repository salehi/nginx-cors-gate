# nginx-cors-proxy

A production-ready, configurable CORS proxy built on nginx with strict origin validation and wildcard domain support.

## The Problem

Managing CORS across multiple backends is a nightmare for DevOps teams:

1. **Inconsistent implementations** — Every backend team implements CORS differently. Python/Flask does it one way, Node/Express another, Go another. Each requires separate maintenance and has its own quirks.

2. **Most implementations are broken** — The dirty secret: most backend CORS implementations only add headers. They don't actually *block* anything. Hit the endpoint with `curl` (no Origin header) and it happily responds. The "protection" only exists because browsers enforce it client-side. This means:
   - Attackers bypass it trivially
   - It's security theater, not actual access control
   - The backend is wide open while devs think it's protected

3. **Debugging is hell** — When something breaks, is it:
   - The backend returning 500 errors?
   - A CORS misconfiguration?
   - Missing allowed origins?
   - Preflight handling bugs?
   - An actual attack being blocked?
   
   You can't tell because every backend logs CORS differently (or not at all), and the browser just shows "CORS error" for everything.

4. **Configuration drift** — Allowed domains lists get out of sync across services. One backend allows `app.example.com`, another allows `*.example.com`, a third has a typo. Good luck auditing that across 20 microservices.

5. **Backend teams don't understand CORS** — They copy-paste middleware configs from Stack Overflow, set `Access-Control-Allow-Origin: *` to "fix" it, and move on. The difference between "adding headers" and "validating + blocking" is lost on most implementations.

## The Solution

Move CORS out of backends entirely. Handle it once, correctly, at the edge.

This project provides a lightweight nginx-based reverse proxy that:

- **Actually blocks requests** — Returns 403 if Origin header is missing or doesn't match allowlist. No Origin = no response. `curl` without headers gets rejected, not served.
- **Single source of truth** — One place to configure allowed domains for all backends. No more drift.
- **Wildcard domains** — `*.example.com` matches any subdomain. Configure once, done.
- **Proper preflight handling** — OPTIONS requests handled correctly with configurable methods/headers
- **Clear separation** — If the proxy returns 403, it's a CORS issue. If it proxies and backend returns 500, it's a backend issue. No more guessing.
- **Backend simplification** — Backends can drop CORS middleware entirely. They just serve requests; the proxy handles access control.
- **Minimal footprint** — ~15MB image based on nginx:alpine. No Node.js, no runtime dependencies.

## Quick Start

```bash
docker run -p 8080:80 \
  -e ALLOWED_DOMAINS="*.example.com,localhost" \
  -e UPSTREAM_HOST=api.example.com \
  -e UPSTREAM_PORT=443 \
  your-image-name
```

Or with docker-compose:

```yaml
version: "3.8"
services:
  cors-proxy:
    build: .
    ports:
      - "8080:80"
    environment:
      ALLOWED_DOMAINS: "*.example.com,localhost,127.0.0.1"
      UPSTREAM_HOST: api.example.com
      UPSTREAM_PORT: "443"
```

## Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ALLOWED_DOMAINS` | Yes | — | Comma-separated list of allowed origins. Supports wildcards like `*.example.com` |
| `UPSTREAM_HOST` | Yes | — | Backend host to proxy requests to |
| `UPSTREAM_PORT` | No | `80` | Backend port |
| `ALLOWED_HEADERS` | No | — | Additional headers to append to defaults |
| `ALLOWED_METHODS` | No | — | Override default methods |

**Default allowed headers:**
`Authorization, Content-Type, X-Requested-With, Accept, Origin, Cache-Control, X-Auth-Token`

**Default allowed methods:**
`GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD`

## Domain Matching

The proxy validates the `Origin` header against your allowed domains:

| Pattern | Matches | Doesn't Match |
|---------|---------|---------------|
| `example.com` | `http://example.com`, `https://example.com:8080` | `http://sub.example.com` |
| `*.example.com` | `http://app.example.com`, `https://api.example.com:3000` | `http://example.com` |
| `localhost` | `http://localhost`, `http://localhost:3000` | `http://127.0.0.1` |

## Health Check

```bash
curl http://localhost:8080/cors/health
# Returns: OK
```

The health endpoint bypasses CORS validation.

## Comparison with Alternatives

| Feature | nginx-cors-proxy | [cors-anywhere](https://github.com/Rob--W/cors-anywhere) | [nginx-cors-plus](https://github.com/shakyShane/nginx-cors-plus) | [docker-nginx-cors](https://github.com/maximillianfx/docker-nginx-cors) |
|---------|------------------|----------------|-----------------|-------------------|
| **Runtime** | nginx (C) | Node.js | nginx | nginx |
| **Image size** | ~15MB | ~150MB+ | ~15MB | ~15MB |
| **Origin validation** | ✅ Allowlist with wildcards | ✅ Whitelist/blacklist | ❌ Allows all | ❌ Allows all (`*`) |
| **Blocks invalid origins** | ✅ Returns 403 | ✅ Configurable | ❌ Proxies anyway | ❌ Proxies anyway |
| **Wildcard domains** | ✅ `*.example.com` | ❌ Exact match only | ❌ N/A | ❌ N/A |
| **Port in origin** | ✅ `localhost:3000` | ✅ | ❌ | ❌ |
| **Preflight handling** | ✅ | ✅ | ✅ | ✅ |
| **Rate limiting** | ❌ (use nginx module) | ✅ Built-in | ❌ | ❌ |
| **Dynamic upstream** | ❌ Fixed at startup | ✅ URL in path | ❌ Env var | ❌ Env var |
| **Config approach** | Env vars + gomplate | Code/env vars | Env var | Static config |
| **Health endpoint** | ✅ `/cors/health` | ❌ | ❌ | ❌ |
| **Production ready** | ✅ | ⚠️ Demo server limited | ⚠️ Basic | ⚠️ Dev only |

### When to Use What

- **nginx-cors-proxy** (this project): Production environments where you need strict origin validation, wildcard support, and minimal resource usage
- **cors-anywhere**: When you need dynamic upstream targets (URL in path) or built-in rate limiting; better for multi-tenant proxy scenarios
- **nginx-cors-plus / docker-nginx-cors**: Quick local development where security doesn't matter

## Architecture

```
┌─────────────┐      ┌─────────────────┐      ┌──────────────┐
│   Browser   │─────▶│  nginx-cors-    │─────▶│   Upstream   │
│ (localhost) │      │     proxy       │      │   Backend    │
└─────────────┘      └─────────────────┘      └──────────────┘
                            │
                     1. Validate Origin
                     2. Block if invalid
                     3. Handle OPTIONS
                     4. Proxy + add headers
```

## Building

```bash
docker build -t nginx-cors-proxy .
```

## Testing

```bash
# Start the proxy with test backend
docker-compose up --build

# Valid origin (should succeed)
curl -H "Origin: http://localhost:3000" http://localhost:8080/
# Response: {"status":"ok","message":"Hello from backend"}

# Missing origin (should fail)
curl http://localhost:8080/
# Response: 403 CORS origin not allowed

# Invalid origin (should fail)
curl -H "Origin: http://evil.com" http://localhost:8080/
# Response: 403 CORS origin not allowed

# Preflight request
curl -X OPTIONS -D - \
  -H "Origin: http://localhost:3000" \
  -H "Access-Control-Request-Method: POST" \
  http://localhost:8080/
# Response: 204 with CORS headers

# Health check (no origin needed)
curl http://localhost:8080/cors/health
# Response: OK
```

## License

MIT
