# HNG Stage 3 DevOps - Monitoring & Alerting (Building on Stage 2)

A production-ready blue/green deployment system enhanced with operational visibility, real-time log monitoring, and Slack alerting for failover events and high error rates.

## 🎯 Overview

**Stage 3** extends the Stage 2 blue/green deployment infrastructure with comprehensive monitoring and alerting:

**Stage 2 Foundation:**

- ✅ Blue/Green deployment architecture
- ✅ NGINX reverse proxy with health checks
- ✅ Automatic failover on upstream failures
- ✅ Docker Compose orchestration

**Stage 3 Enhancements (This Stage):**

- 🆕 **Custom NGINX Logging** capturing pool, release, upstream status, and latency
- 🆕 **Real-time Log Monitoring** with Python-based watcher service
- 🆕 **Slack Alerts** for failover detection and elevated error rates
- 🆕 **Error Rate Calculation** over sliding window (configurable threshold)
- 🆕 **Alert Deduplication** with cooldown periods
- 🆕 **Maintenance Mode** for suppressing alerts during planned work
- 🆕 **Chaos Testing** endpoints for validating monitoring behavior

## ✨ What's New in Stage 3

This stage adds **operational visibility and actionable alerts** without modifying the application images from Stage 2:

- Instrumented NGINX access logs to record which pool served each request
- Python log-watcher that tails NGINX logs in real-time
- Slack notifications when:
  - Failover occurs (Blue→Green or Green→Blue)
  - Upstream 5xx error rates breach configurable thresholds
- Zero coupling to request path (all monitoring via logs)
- Operator-friendly runbook for responding to alerts

## 🧪 Testing Failover and Alerts

### Automated Test Suite

Run the comprehensive monitoring test:

```bash
./test-monitoring.sh
```

This script tests:

- ✅ NGINX custom log format
- ✅ Log volume sharing
- ✅ Watcher startup and configuration
- ✅ Baseline traffic monitoring
- ✅ Chaos injection and failover detection
- ✅ Error rate monitoring
- ✅ Recovery after chaos
- ✅ Alert cooldown mechanism

### Manual Chaos Testing

#### Test 1: Trigger Failover Alert

```bash
# 1. Activate chaos mode on Blue (causes 500 errors)
curl -X POST http://localhost:8081/chaos/start?mode=error

# 2. Send traffic - NGINX will failover to Green
for i in {1..30}; do
  curl -s http://localhost:8080/version > /dev/null
  sleep 0.2
done

# 3. Check Slack for "Failover Detected" alert
# 4. Verify in logs
docker logs alert_watcher | grep "Failover detected"
```

**Expected Slack Alert:**

```
🔄 Failover Detected
Pool switched: `blue` → `green`
Timestamp: 2025-10-31 XX:XX:XX
Action: Check health of `blue` container
```

#### Test 2: Trigger Error-Rate Alert

```bash
# 1. Make BOTH pools fail to force errors through
curl -X POST http://localhost:8081/chaos/start?mode=error
curl -X POST http://localhost:8082/chaos/start?mode=error

# 2. Send 250 requests to fill the error window
for i in {1..250}; do
  curl -s http://localhost:8080/version > /dev/null
  sleep 0.05
done

# 3. Check Slack for "High Error Rate Detected" alert
# 4. Verify in logs
docker logs alert_watcher | grep "High error rate"
```

**Expected Slack Alert:**

```
⚠️ High Error Rate Detected
Error rate: `X.XX%` (threshold: 2.0%)
Window: Last 200 requests
Current pool: `green`
Timestamp: 2025-10-31 XX:XX:XX
Action: Inspect upstream logs and consider pool toggle
```

#### Stop Chaos and Verify Recovery

```bash
# Stop chaos on both pools
curl -X POST http://localhost:8081/chaos/stop
curl -X POST http://localhost:8082/chaos/stop

# Send recovery traffic
for i in {1..20}; do
  curl -s http://localhost:8080/version > /dev/null
  sleep 0.3
done
```

## 📊 Viewing Logs and Monitoring

### NGINX Access Logs (Custom Format)

View the structured logs showing pool, release, upstream status, and latency:

```bash
# View last 20 log lines
docker exec nginx_proxy tail -20 /var/log/nginx/access.log

# Follow logs in real-time
docker exec nginx_proxy tail -f /var/log/nginx/access.log

# Example log line:
# 172.19.0.1 - - [31/Oct/2025:12:44:39 +0000] "GET /version HTTP/1.1" 200 57 "-" "curl/8.5.0"
# pool=blue release=blue-v1.0.0 upstream_status=200 upstream=172.19.0.3:3000
# request_time=0.006 upstream_response_time=0.007
```

### Log Watcher Output

```bash
# View watcher console output
docker logs alert_watcher

# Follow watcher in real-time
docker logs -f alert_watcher

# Search for specific events
docker logs alert_watcher | grep "Failover\|Error rate\|Slack alert"
```

### Container Health and Status

```bash
# Check all services
docker-compose ps

# View specific service logs
docker logs nginx_proxy
docker logs app_blue
docker logs app_green

# Check resource usage
docker stats --no-stream
```

## 📋 Prerequisites

- Docker 20.10+ (daemon installed and running)
- Docker Compose v2 (or docker-compose v1.27+)
- Slack workspace with incoming webhook (for alerts)
- Internet access for image pulls

## ⚙️ Architecture

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │
       ▼
┌──────────────────┐
│  NGINX (8080)    │  ← Custom log format with pool/release/status
└────┬────────┬────┘
     │        │
     ▼        ▼
┌─────────┐ ┌─────────┐
│ Blue    │ │ Green   │
│ (8081)  │ │ (8082)  │
└─────────┘ └─────────┘
     │           │
     └───────┬───┘
             ▼
    ┌─────────────────┐
    │  Log Watcher    │  ← Monitors logs, sends Slack alerts
    │  (Python)       │
    └─────────────────┘
             │
             ▼
    ┌─────────────────┐
    │     Slack       │
    └─────────────────┘
```

## 🚀 Quick Start

### 1. Configure Slack Webhook

Create a Slack incoming webhook and add it to `.env`:

```bash
# Get webhook from: https://api.slack.com/messaging/webhooks
# Edit .env and set:
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

### 2. Configure Environment Variables

The `.env` file contains all configuration:

```bash
# Application Images
BLUE_IMAGE=yimikaade/wonderful:devops-stage-two
GREEN_IMAGE=yimikaade/wonderful:devops-stage-two

# Active Pool (blue or green)
ACTIVE_POOL=blue

# Release Identifiers
RELEASE_ID_BLUE=blue-v1.0.0
RELEASE_ID_GREEN=green-v1.0.0

# Application Port
PORT=3000

# Slack Webhook for Alerts
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL

# Monitoring Thresholds
ERROR_RATE_THRESHOLD=2.0        # Alert when error rate exceeds 2%
WINDOW_SIZE=200                 # Calculate error rate over 200 requests
ALERT_COOLDOWN_SEC=300          # Minimum 5 minutes between duplicate alerts

# Maintenance Mode (suppresses alerts)
MAINTENANCE_MODE=false
```

### 3. Start the System

```bash
# Build and start all services
docker-compose up -d --build

# Wait for health checks to pass
sleep 15

# Verify all containers are healthy
docker-compose ps
```

Expected output:

```
NAME            STATE       PORTS
nginx_proxy     Up          0.0.0.0:8080->80/tcp
app_blue        Up (healthy) 0.0.0.0:8081->3000/tcp
app_green       Up (healthy) 0.0.0.0:8082->3000/tcp
alert_watcher   Up
```

### 4. Verify System is Running

```bash
# Test NGINX proxy
curl http://localhost:8080/version

# Test Blue directly
curl http://localhost:8081/version

# Test Green directly
curl http://localhost:8082/version

# Check watcher logs
docker logs alert_watcher --tail=20
```

You should receive a **"Monitoring Started"** alert in Slack! ✅

## 🔧 Configuration Reference

### Alert Thresholds

Tune monitoring sensitivity by editing `.env`:

```bash
# More sensitive (alert on 1% errors)
ERROR_RATE_THRESHOLD=1.0

# Larger sample size (more stable, less noisy)
WINDOW_SIZE=500

# Faster re-alerting (2 minutes instead of 5)
ALERT_COOLDOWN_SEC=120
```

### Maintenance Mode

Suppress alerts during planned maintenance:

```bash
# Edit .env
MAINTENANCE_MODE=true

# Restart watcher
docker-compose restart alert_watcher

# Perform maintenance...

# Re-enable alerts
MAINTENANCE_MODE=false
docker-compose restart alert_watcher
```

### Switch Active Pool

```bash
# Edit .env and change ACTIVE_POOL
ACTIVE_POOL=green

# Restart NGINX to apply
docker-compose restart nginx
```

## 📁 Project Structure

```
.
├── docker-compose.yml          # Service orchestration
├── .env                        # Environment variables (configure here!)
├── Dockerfile.nginx            # NGINX container with log file fix
├── Dockerfile.watcher          # Python log watcher container
├── nginx.conf.template         # NGINX config with custom log format
├── entrypoint.sh               # NGINX startup script
├── log_watcher.py              # Python monitoring and alerting script
├── requirements.txt            # Python dependencies
├── test-monitoring.sh          # Comprehensive test suite
├── test-failover.sh            # Failover-specific test
├── RUNBOOK.md                  # Operational procedures
├── DECISION.md                 # Design decisions
└── README.md                   # This file
```

## 🛠️ Key Components

### NGINX Custom Log Format

Configured in `nginx.conf.template`:

```nginx
log_format detailed '$remote_addr - $remote_user [$time_local] '
                   '"$request" $status $body_bytes_sent '
                   '"$http_referer" "$http_user_agent" '
                   'pool=$upstream_http_x_app_pool '
                   'release=$upstream_http_x_release_id '
                   'upstream_status=$upstream_status '
                   'upstream=$upstream_addr '
                   'request_time=$request_time '
                   'upstream_response_time=$upstream_response_time';
```

### Log Watcher Features

- **Real-time log tailing** with automatic parsing
- **Failover detection** by tracking pool changes
- **Error-rate calculation** over sliding window
- **Alert deduplication** with configurable cooldown
- **Maintenance mode** for planned operations
- **Structured Slack notifications** with color coding

### Alert Types

| Alert              | Trigger         | Color  | Cooldown |
| ------------------ | --------------- | ------ | -------- |
| Monitoring Started | Watcher startup | Green  | Once     |
| Failover Detected  | Pool change     | Yellow | 300s     |
| High Error Rate    | >2% 5xx errors  | Red    | 300s     |
| Monitor Crashed    | Fatal error     | Red    | Once     |

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

## 🐛 Troubleshooting

### No Alerts Received

**Check Slack webhook configuration:**

```bash
docker logs alert_watcher | grep "Slack webhook"
# Should show: "Slack webhook: Configured"

# Test webhook manually
curl -X POST https://hooks.slack.com/services/YOUR/WEBHOOK/URL \
  -H 'Content-Type: application/json' \
  -d '{"text":"Test alert"}'
```

**Verify watcher is processing logs:**

```bash
docker logs alert_watcher | tail -20
# Should show request counts and pool information
```

**Check alert cooldown:**

```bash
# Restart watcher to reset cooldowns
docker-compose restart alert_watcher
```

### Watcher Not Detecting Traffic

**Verify log file exists and has content:**

```bash
docker exec nginx_proxy ls -lh /var/log/nginx/access.log
# Should show a regular file, NOT a symlink

docker exec nginx_proxy tail -5 /var/log/nginx/access.log
# Should show log lines with pool= release= etc.
```

**If logs are empty or symlinked:**

```bash
# Rebuild nginx with the fix
docker-compose down
docker-compose build --no-cache nginx
docker-compose up -d
```

### Containers Not Healthy

```bash
# Check container health
docker-compose ps

# View specific container logs
docker logs app_blue
docker logs app_green

# Restart unhealthy containers
docker-compose restart app_blue app_green
```

### Image Pull Failures

```bash
# Test connectivity
docker pull nginx:alpine
docker pull python:3.11-slim

# Restart Docker daemon
sudo systemctl restart docker

# Check proxy settings if behind corporate firewall
cat /etc/systemd/system/docker.service.d/http-proxy.conf
```

### High Memory Usage

```bash
# Check resource usage
docker stats

# Reduce window size in .env to use less memory
WINDOW_SIZE=50

# Restart watcher
docker-compose restart alert_watcher
```

## 📚 Additional Resources

- **Stage 2 Foundation:** Blue/Green deployment setup (prerequisite completed)
- **Operational Procedures:** See `RUNBOOK.md` for detailed operator instructions
- **Design Decisions:** See `DECISION.md` for architectural choices and rationale
- **Test Scripts:**
  - `test-monitoring.sh` - Full Stage 3 test suite
  - `test-failover.sh` - Failover-specific tests (Stage 2 baseline)

## 🎓 Learning Outcomes

**Stage 3 builds on Stage 2** to demonstrate:

**From Stage 2:**

- ✅ Blue/Green deployment architecture
- ✅ NGINX reverse proxy configuration
- ✅ Health checks and automatic failover
- ✅ Docker Compose multi-container orchestration

**New in Stage 3:**

- 🆕 Custom structured logging formats
- 🆕 Real-time log processing in Python
- 🆕 Slack integration for operational alerts
- 🆕 Sliding window error rate calculation
- 🆕 Alert deduplication and rate limiting
- 🆕 Chaos engineering for resilience testing
- 🆕 Zero-downtime monitoring (no app modifications)
- 🆕 Production-ready alerting patterns

## 📋 Stage 3 Acceptance Criteria

This implementation meets all Stage 3 requirements:

- ✅ NGINX logs show pool, release, upstream status, and address for each request
- ✅ Python log-watcher tails NGINX logs and posts alerts to Slack
- ✅ Detects and alerts on failover events (Blue↔Green)
- ✅ Detects and alerts on elevated upstream 5xx error rates over sliding window
- ✅ Environment variables in `.env` configure Slack webhook, thresholds, and cooldowns
- ✅ No modifications to app images (Stage 2 images unchanged)
- ✅ Zero coupling to request path (alerts from logs only)
- ✅ Shared log volume for NGINX and watcher
- ✅ Alerts are deduplicated and rate-limited
- ✅ Runbook documented and operator-friendly
- ✅ Chaos drill generates failover alert in Slack
- ✅ Error-rate simulation generates error-rate alert in Slack

## 🤝 Contributing

For issues or improvements:

1. Check existing alerts in Slack and watcher logs
2. Review `RUNBOOK.md` for troubleshooting steps
3. Test changes with `./test-monitoring.sh`
4. Ensure all Stage 3 acceptance criteria are met

## 📄 License

This project is part of **HNG13 Stage 3 DevOps track** (Monitoring & Alerting).

**Prerequisites:** Completion of Stage 2 (Blue/Green Deployment)

---

**Need Help?**

- Review the `RUNBOOK.md` for operational procedures
- Check container logs: `docker-compose logs`
- Verify Slack webhook: `docker logs alert_watcher | grep Slack`
- Run Stage 3 tests: `./test-monitoring.sh`
- Verify Stage 2 baseline still works: `./test-failover.sh`
