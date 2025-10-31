#!/usr/bin/env python3
"""
NGINX Log Watcher - Monitors access logs and sends Slack alerts
"""

import os
import re
import time
import json
import requests
from collections import deque
from datetime import datetime, timedelta

# Configuration from environment variables
SLACK_WEBHOOK_URL = os.getenv('SLACK_WEBHOOK_URL', '')
ERROR_RATE_THRESHOLD = float(os.getenv('ERROR_RATE_THRESHOLD', '2.0'))
WINDOW_SIZE = int(os.getenv('WINDOW_SIZE', '200'))
ALERT_COOLDOWN_SEC = int(os.getenv('ALERT_COOLDOWN_SEC', '10')) # Reduced for testing
MAINTENANCE_MODE = os.getenv('MAINTENANCE_MODE', 'false').lower() == 'true'
LOG_FILE = '/var/log/nginx/access.log'

# Alert state tracking
last_pool = None
last_failover_alert = None
last_error_rate_alert = None
request_window = deque(maxlen=WINDOW_SIZE)

# Log parsing regex
LOG_PATTERN = re.compile(
    r'pool=(?P<pool>\S+) '
    r'release=(?P<release>\S+) '
    r'upstream_status=(?P<upstream_status>\S+) '
    r'upstream=(?P<upstream>\S+) '
    r'request_time=(?P<request_time>\S+) '
    r'upstream_response_time=(?P<upstream_response_time>\S+)'
)

def send_slack_alert(message, color="warning"):
    """Send alert to Slack webhook"""
    if not SLACK_WEBHOOK_URL:
        print(f"⚠️  No Slack webhook configured. Alert: {message}")
        return False
    
    payload = {
        "attachments": [{
            "color": color,
            "title": "🚨 Blue/Green Deployment Alert",
            "text": message,
            "footer": "NGINX Monitoring",
            "ts": int(time.time())
        }]
    }
    
    try:
        response = requests.post(
            SLACK_WEBHOOK_URL,
            json=payload,
            timeout=10
        )
        response.raise_for_status()
        print(f"✅ Slack alert sent: {message}")
        return True
    except Exception as e:
        print(f"❌ Failed to send Slack alert: {e}")
        return False

def check_cooldown(last_alert_time):
    """Check if alert cooldown period has passed"""
    if last_alert_time is None:
        return True
    
    elapsed = (datetime.now() - last_alert_time).total_seconds()
    return elapsed >= ALERT_COOLDOWN_SEC

def calculate_error_rate():
    """Calculate error rate over the sliding window"""
    if len(request_window) == 0:
        return 0.0
    
    error_count = sum(1 for status in request_window if status >= 500)
    return (error_count / len(request_window)) * 100

def parse_log_line(line):
    """Parse NGINX log line and extract relevant fields"""
    match = LOG_PATTERN.search(line)
    if not match:
        return None
    
    data = match.groupdict()
    
    # Parse upstream status (may contain multiple values for retries)
    upstream_status = data['upstream_status']
    if ',' in upstream_status:
        # Take the last status (final result)
        statuses = upstream_status.split(',')
        final_status = int(statuses[-1].strip())
    elif upstream_status == '-':
        final_status = 0
    else:
        final_status = int(upstream_status)
    
    return {
        'pool': data['pool'],
        'release': data['release'],
        'upstream_status': final_status,
        'upstream': data['upstream'],
        'request_time': float(data['request_time']) if data['request_time'] != '-' else 0,
        'upstream_response_time': float(data['upstream_response_time']) if data['upstream_response_time'] != '-' else 0
    }

def check_failover(current_pool):
    """Detect and alert on pool failover"""
    global last_pool, last_failover_alert
    
    if current_pool == '-':
        return
    
    # First request - just record the pool
    if last_pool is None:
        last_pool = current_pool
        print(f"📊 Initial pool detected: {current_pool}")
        return
    
    # Pool changed - failover detected
    if current_pool != last_pool:
        if MAINTENANCE_MODE:
            print(f"🔧 Maintenance mode: Failover {last_pool} → {current_pool} (suppressed)")
            last_pool = current_pool
            return
        
        if check_cooldown(last_failover_alert):
            message = (
                f"🔄 *Failover Detected*\n"
                f"Pool switched: `{last_pool}` → `{current_pool}`\n"
                f"Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
                f"Action: Check health of `{last_pool}` container"
            )
            
            if send_slack_alert(message, color="warning"):
                last_failover_alert = datetime.now()
        
        last_pool = current_pool
        print(f"🔄 Failover detected: {last_pool} → {current_pool}")

def check_error_rate():
    """Check and alert on elevated error rates"""
    global last_error_rate_alert
    
    if len(request_window) < WINDOW_SIZE:
        return  # Wait until window is full
    
    error_rate = calculate_error_rate()
    
    if error_rate > ERROR_RATE_THRESHOLD:
        if MAINTENANCE_MODE:
            print(f"🔧 Maintenance mode: High error rate {error_rate:.2f}% (suppressed)")
            return
        
        if check_cooldown(last_error_rate_alert):
            message = (
                f"⚠️ *High Error Rate Detected*\n"
                f"Error rate: `{error_rate:.2f}%` (threshold: {ERROR_RATE_THRESHOLD}%)\n"
                f"Window: Last {WINDOW_SIZE} requests\n"
                f"Current pool: `{last_pool}`\n"
                f"Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
                f"Action: Inspect upstream logs and consider pool toggle"
            )
            
            if send_slack_alert(message, color="danger"):
                last_error_rate_alert = datetime.now()
        
        print(f"⚠️  High error rate: {error_rate:.2f}%")

def tail_log_file(filename):
    """Tail log file and yield new lines"""
    with open(filename, 'r') as f:
        # Read all existing lines first
        for line in f:
            yield line.strip()
        
        # Then continuously read new lines
        while True:
            line = f.readline()
            if line:
                yield line.strip()
            else:
                time.sleep(0.1)

def main():
    """Main monitoring loop"""
    print("=" * 60)
    print("🔍 NGINX Log Watcher Started")
    print("=" * 60)
    print(f"Log file: {LOG_FILE}")
    print(f"Slack webhook: {'Configured' if SLACK_WEBHOOK_URL else 'Not configured'}")
    print(f"Error rate threshold: {ERROR_RATE_THRESHOLD}%")
    print(f"Window size: {WINDOW_SIZE} requests")
    print(f"Alert cooldown: {ALERT_COOLDOWN_SEC} seconds")
    print(f"Maintenance mode: {MAINTENANCE_MODE}")
    print("=" * 60)
    
    # Wait for log file to exist
    while not os.path.exists(LOG_FILE):
        print(f"⏳ Waiting for log file: {LOG_FILE}")
        time.sleep(2)
    
    print(f"✅ Log file found, starting monitoring...")
    
    # Send startup notification
    if SLACK_WEBHOOK_URL and not MAINTENANCE_MODE:
        send_slack_alert(
            f"✅ *Monitoring Started*\n"
            f"Watching for failovers and error rates\n"
            f"Threshold: {ERROR_RATE_THRESHOLD}% over {WINDOW_SIZE} requests",
            color="good"
        )
    
    # Start tailing logs
    for line in tail_log_file(LOG_FILE):
        data = parse_log_line(line)
        
        if data:
            # Track upstream status
            request_window.append(data['upstream_status'])
            
            # Check for failover
            check_failover(data['pool'])
            
            # Check error rate
            check_error_rate()
            
            # Log summary
            if data['upstream_status'] >= 500:
                print(f"❌ Error: {data['upstream_status']} from {data['pool']} ({data['upstream']})")
            else:
                # Only print every 10th success to reduce noise
                if len(request_window) % 10 == 0:
                    error_rate = calculate_error_rate()
                    print(f"✅ {len(request_window)} requests | Pool: {data['pool']} | Error rate: {error_rate:.2f}%")

if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print("\n👋 Monitoring stopped")
    except Exception as e:
        print(f"💥 Fatal error: {e}")
        if SLACK_WEBHOOK_URL:
            send_slack_alert(
                f"🚨 *Monitor Crashed*\n"
                f"Error: {str(e)}\n"
                f"Action: Check log_watcher container logs",
                color="danger"
            )
        raise