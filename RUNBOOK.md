# Operations Runbook - Blue/Green Deployment

## Overview

This runbook provides guidance for responding to alerts from the Blue/Green deployment monitoring system.

## Alert Types

### 1. 🔄 Failover Detected

**Alert Message:**
🔄 Failover Detected
Pool switched: blue → green
Timestamp: 2025-10-26 20:30:15
Action: Check health of blue container
**What It Means:**

- Traffic has automatically switched from one pool to another
- The primary pool (Blue or Green) is experiencing issues
- NGINX has marked the primary as unhealthy

**Immediate Actions:**

1. Check the health of the failed pool:

```bash
   docker logs app_blue --tail=50
   # or
   docker logs app_green --tail=50
```

2. Verify container status:

```bash
   docker-compose ps
```

3. Check upstream health:

```bash
   curl http://localhost:8081/healthz  # Blue
   curl http://localhost:8082/healthz  # Green
```

**Investigation Steps:**

- Review application logs for errors
- Check resource utilization (CPU, memory)
- Verify database/dependency connectivity
- Look for recent deployments or changes

**Resolution:**

- If temporary: Wait for automatic recovery (check logs in 5-10 minutes)
- If persistent:

```bash
  # Restart the failed container
  docker-compose restart app_blue

  # Or trigger manual failback after fixing
  curl -X POST http://localhost:8081/chaos/stop
```

---

### 2. ⚠️ High Error Rate Detected

**Alert Message:**
⚠️ High Error Rate Detected
Error rate: 5.50% (threshold: 2.0%)
Window: Last 200 requests
Current pool: green
Timestamp: 2025-10-26 20:35:22
Action: Inspect upstream logs and consider pool toggle
**What It Means:**

- The active pool is returning >2% 5xx errors
- Quality of service has degraded
- May indicate application issues or resource constraints

**Immediate Actions:**

1. Check current error patterns:

```bash
   docker logs nginx_proxy | grep "upstream_status=5"
```

2. Inspect active pool logs:

```bash
   docker logs app_green --tail=100 | grep -i error
```

3. Check resource usage:

```bash
   docker stats --no-stream
```

**Investigation Steps:**

- Identify error types (500, 502, 503, 504)
- Check for resource exhaustion
- Review recent traffic patterns
- Verify dependencies (database, APIs, etc.)

**Resolution Options:**

**Option A: Wait and Monitor**

```bash
# If transient, errors may self-resolve
docker logs alert_watcher -f
```

**Option B: Manual Pool Toggle**

```bash
# Switch to the other pool
docker-compose stop app_green
# Traffic will fail to app_blue
```

**Option C: Scale/Restart**

```bash
# Restart the degraded pool
docker-compose restart app_green
```

---

### 3. ✅ Recovery / Monitoring Started

**Alert Message:**
✅ Monitoring Started
Watching for failovers and error rates
Threshold: 2.0% over 200 requests
**What It Means:**

- Monitoring system has started successfully
- Normal operations

**Action:**

- No action required
- Informational only

---

## Maintenance Procedures

### Planned Pool Toggle (No Alerts)

When performing planned maintenance:

1. Enable maintenance mode:

```bash
   echo "MAINTENANCE_MODE=true" >> .env
   docker-compose restart alert_watcher
```

2. Perform your maintenance:

```bash
   # Update .env to switch pools
   # ACTIVE_POOL=green
   docker-compose restart nginx
```

3. Disable maintenance mode:

```bash
   sed -i 's/MAINTENANCE_MODE=true/MAINTENANCE_MODE=false/' .env
   docker-compose restart alert_watcher
```

### Suppressing Alerts Temporarily

```bash
# Stop the watcher during maintenance
docker-compose stop alert_watcher

# Perform maintenance...

# Restart watcher
docker-compose start alert_watcher
```

---

## Monitoring Commands

### View Real-Time Logs

```bash
# NGINX access logs with pool info
docker exec nginx_proxy tail -f /var/log/nginx/access.log

# Watcher alerts
docker logs alert_watcher -f

# Application logs
docker logs app_blue -f
docker logs app_green -f
```

### Check Current State

```bash
# Which pool is active?
curl -s http://localhost:8080/version | grep -i x-app-pool

# Error rate check
docker logs alert_watcher | grep "Error rate"

# Container health
docker-compose ps
```

### Manual Chaos Testing

```bash
# Trigger failover
curl -X POST http://localhost:8081/chaos/start?mode=error

# Wait for alert in Slack...

# Stop chaos
curl -X POST http://localhost:8081/chaos/stop
```

---

## Alert Configuration

### Tuning Thresholds

Edit `.env` to adjust sensitivity:

```bash
# More sensitive (alert on 1% errors)
ERROR_RATE_THRESHOLD=1.0

# Larger sample size
WINDOW_SIZE=500

# Faster re-alerting (2 minutes)
ALERT_COOLDOWN_SEC=120
```

Then restart:

```bash
docker-compose restart alert_watcher
```

### Slack Webhook Setup

1. Go to https://api.slack.com/messaging/webhooks
2. Create incoming webhook
3. Copy webhook URL
4. Update `.env`:

```bash
   SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

5. Restart:

```bash
   docker-compose restart alert_watcher
```

---

## Troubleshooting

### No Alerts Received

1. Check webhook configuration:

```bash
   docker logs alert_watcher | grep "Slack"
```

2. Verify webhook URL:

```bash
   # Test webhook manually
   curl -X POST $SLACK_WEBHOOK_URL \
     -H 'Content-Type: application/json' \
     -d '{"text":"Test alert"}'
```

3. Check cooldown hasn't suppressed alerts:

```bash
   docker logs alert_watcher | grep "cooldown"
```

### Watcher Not Starting

```bash
# Check watcher logs
docker logs alert_watcher

# Verify log volume
docker exec nginx_proxy ls -la /var/log/nginx/

# Restart watcher
docker-compose restart alert_watcher
```

### False Positive Alerts

Increase thresholds:

```bash
ERROR_RATE_THRESHOLD=5.0  # More tolerant
WINDOW_SIZE=500           # Larger sample
```

