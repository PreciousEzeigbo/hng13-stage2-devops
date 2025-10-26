# hng13-stage2-devops

Simple Docker Compose blue/green demo with nginx as a reverse proxy.

This repository provides a small Compose stack that routes traffic to either `app_blue` or `app_green` upstreams. It is intended as a demonstration of blue/green wiring and template-based nginx configuration.

## What I changed to make it runnable

- Replaced missing custom images with `nginxdemos/hello:latest` in `.env` for quick validation.
- Added `Dockerfile.nginx` (minimal, based on `nginx:alpine`) so the `nginx` service can be built from the repo.
- Added `nginx.conf.template` which `nginx` will render on container start using `envsubst` and write to `/etc/nginx/conf.d/default.conf`.
- Added `DECISION.md` (explanation of choices and troubleshooting steps).

## Prerequisites

- Docker (daemon installed and running)
- docker-compose (v1) or Docker Compose v2 (recommended: `docker compose`)

Note: This project performs image pulls from Docker Hub. If your environment blocks registry access (DNS/HTTP/proxy), see Troubleshooting below.

## Environment (.env)

The project reads values from `.env`. Key variables:

- `BLUE_IMAGE` — image for the blue app (default used during testing: `nginxdemos/hello:latest`).
- `GREEN_IMAGE` — image for the green app (default used during testing: `nginxdemos/hello:latest`).
- `ACTIVE_POOL` — `blue` or `green` (which upstream nginx should proxy to)
- `RELEASE_ID_BLUE` / `RELEASE_ID_GREEN` — metadata env vars
- `PORT` — container port apps listen on (set to `80` by default in `.env` here)

Example `.env` values (already present in repo):

```
BLUE_IMAGE=nginxdemos/hello:latest
GREEN_IMAGE=nginxdemos/hello:latest
ACTIVE_POOL=blue
RELEASE_ID_BLUE=blue-v1.0
RELEASE_ID_GREEN=green-v1.0
PORT=80
```

## How to run

Start the stack (from the repo root):

```bash
# recommended when using Docker Compose v2
docker compose up --build -d

# or with classic docker-compose v1
docker-compose up --build -d
```

This will build the `nginx` image and pull the app images. Nginx will render the config using `ACTIVE_POOL` and proxy to either `app_blue` (host port 8081) or `app_green` (host port 8082) depending on the value of `ACTIVE_POOL`.

Access the proxy at: http://localhost:8080

Direct app endpoints (for testing):

- Blue app: http://localhost:8081
- Green app: http://localhost:8082

To stop and remove containers:

```bash
docker compose down
# or
docker-compose down
```

## Troubleshooting: image pull / DNS / network

If `docker compose up --build` fails while pulling base images (errors mentioning `failed to resolve source metadata` or DNS timeouts), try:

1. Manually pull the images to see the specific error:

```bash
docker pull nginx:alpine
docker pull nginxdemos/hello:latest
```

2. Restart Docker daemon and retry:

```bash
sudo systemctl restart docker
docker compose up --build -d
```

3. Check local DNS resolver (`/etc/resolv.conf`) and network connectivity. If you're behind a corporate proxy or VPN, ensure Docker is configured to use the proxy or temporarily disable the VPN.

4. Workaround for offline machines: on a machine with internet access, pull the required images and save them:

```bash
# on networked machine
docker pull nginx:alpine
docker pull nginxdemos/hello:latest
docker save -o images.tar nginx:alpine nginxdemos/hello:latest

# on target machine
docker load -i images.tar
```

## How to switch active pool

Edit `.env` and set `ACTIVE_POOL=blue` or `ACTIVE_POOL=green`, then restart nginx so it regenerates the config (or recreate the container):

```bash
docker compose restart nginx
# or
docker compose up -d --no-deps --build nginx
```

## Files of interest

- `docker-compose.yml` — service definitions and ports
- `.env` — environment variables used in compose
- `Dockerfile.nginx` — minimal Dockerfile for nginx service
- `nginx.conf.template` — nginx template file (rendered by envsubst)
- `DECISION.md` — notes on decisions taken and troubleshooting

## Next steps / recommendations

- Replace the temporary public images with your actual app images, or add Dockerfiles for the app services and build them locally so the stack is fully reproducible.
- Add simple healthchecks for the `app_*` services and update nginx config to use them if needed.
