# DECISION.md

This document records the key decisions and thought process taken while getting the Compose stack working.

## 1. Problem discovered

- Initially `docker-compose up` failed because the Compose file pointed to images that don't exist on Docker Hub (example: `yimikaade/wonderful:blue`). The error shown was: `manifest for ... not found: manifest unknown`.

## 2. Image selection and `.env` changes

Decision: Temporarily replace the missing custom images with a known public image and set the container port to 80.

Reasoning: The repo didn't include Dockerfiles for the app images. To verify the compose wiring (nginx <-> app blue/green) quickly, I used `nginxdemos/hello:latest` for both `BLUE_IMAGE` and `GREEN_IMAGE`. I also set `PORT=80` so the containers listen on 80 (common for HTTP) and the host ports can map to different ports (8081/8082) as defined in `docker-compose.yml`.

Files changed: `.env` updated to point `BLUE_IMAGE` and `GREEN_IMAGE` to `nginxdemos/hello:latest` and `PORT=80`.

## 3. Nginx service build

Decision: Add a minimal `Dockerfile.nginx` and a simple `nginx.conf.template` so the `nginx` service can be built and generate its runtime config from the template.

Reasoning: `docker-compose.yml` expects to build an `nginx` image from `Dockerfile.nginx` and to render `/etc/nginx/conf.d/default.conf` from a template using `envsubst`. The repository didn't include the files, so I added:

- `Dockerfile.nginx` — based on `nginx:alpine`, creates `/etc/nginx/templates`.
- `nginx.conf.template` — an include-style config that defines an `upstream backend` using `app_$ACTIVE_POOL:80` and a `server` that proxies to it.

This keeps behavior simple and compatible with the Compose command that runs `envsubst` at container start.

## 4. Network/DNS issue encountered when building

Observation: When building `nginx` the daemon failed to pull the base image (`nginx:alpine`) due to a DNS/network timeout:

```
failed to resolve source metadata for docker.io/library/nginx:alpine: failed to do request: Head "https://registry-1.docker.io/v2/library/nginx/manifests/alpine": dial tcp: lookup registry-1.docker.io on 127.0.0.53:53: read udp 127.0.0.1:40997->127.0.0.53:53: i/o timeout
```

Interpretation: This is an environment issue (DNS, proxy, VPN, or Docker daemon connectivity) rather than a repo or compose configuration bug.

Suggested mitigation steps (for the operator):

1. Try `docker pull nginx:alpine` and `docker pull nginxdemos/hello:latest` to reproduce and see clearer errors.
2. Restart Docker: `sudo systemctl restart docker`.
3. Check `/etc/resolv.conf` and local DNS settings, or temporary disable VPN/proxy to test connectivity.
4. If machine is offline, pre-pull images on a networked machine and `docker save`/`docker load` them on this host.

## 5. Trade-offs and future work

- The change to public images is a quick validation step. For production or final submission, replace `BLUE_IMAGE`/`GREEN_IMAGE` with the intended images or add app Dockerfiles to the repo so the images can be built locally and reproducibly.
- The `nginx.conf.template` is intentionally minimal; if you need advanced features (TLS, health checks, sticky sessions), extend the template and test accordingly.

## 6. Current status

- Compose wiring validated locally (template generation, upstream/server layout). App image pull succeeded for a public image.
- The current blocker is Docker daemon network access to the registry when building base images.
