# Production Deployment Checklist

Use this checklist to ensure a complete and successful production deployment of the blockchain data ingestion service.

## Pre-Deployment

### Local Preparation

- [ ] Repository cloned locally
- [ ] `.env.production` reviewed and customized
  - [ ] Strong `CLICKHOUSE_PASSWORD` set
  - [ ] `MAX_DATA_SIZE_GB` appropriate for disk capacity
  - [ ] `ENABLE_TIME_LIMIT` set to `false` for continuous operation
  - [ ] RPC URLs configured (Bitcoin, Solana)
- [ ] SSH access to remote server verified
- [ ] SSH config has `typeless_sandbox` entry OR `REMOTE_USER` environment variable set

### Server Preparation

- [ ] Server meets minimum requirements:
  - [ ] Ubuntu 20.04+ or Debian 11+
  - [ ] 4GB+ RAM (8GB recommended)
  - [ ] 100GB+ available disk space
  - [ ] 2+ CPU cores
- [ ] Docker installed (version 20.10+)
  ```bash
  ssh typeless_sandbox "docker --version"
  ```
- [ ] Docker Compose v2 installed
  ```bash
  ssh typeless_sandbox "docker compose version"
  ```
- [ ] Required ports available (8123/8125/8126, 8000, 3001, 9001)
  ```bash
  ssh typeless_sandbox "ss -tlnp | grep -E '8123|8000|3001|9001'"
  ```
- [ ] Sufficient disk space
  ```bash
  ssh typeless_sandbox "df -h"
  ```

## Deployment

### Automated Deployment

- [ ] Run deployment script
  ```bash
  ./scripts/deploy-to-hetzner.sh
  ```
- [ ] Script completed without errors
- [ ] Note the assigned ClickHouse port (8123, 8125, or 8126)
- [ ] Note the remote server IP address
- [ ] Access URLs displayed correctly

### Verify Initial Deployment

- [ ] SSH to server
  ```bash
  ssh typeless_sandbox
  cd /opt/blockchain-ingestion
  ```
- [ ] All containers running
  ```bash
  docker compose -f docker-compose.production.yml ps
  ```
  Expected: 3 containers running (clickhouse, collector, dashboard)
- [ ] ClickHouse accessible
  ```bash
  docker exec blockchain_clickhouse_prod clickhouse-client --password='YOUR_PASSWORD' --query="SELECT 1"
  ```
- [ ] Collector API responding
  ```bash
  curl http://localhost:8000/health
  ```
- [ ] Dashboard accessible from browser
  - Open: `http://<SERVER_IP>:3001`

## Post-Deployment Configuration

### systemd Service Setup

- [ ] Copy service file
  ```bash
  sudo cp scripts/blockchain-ingestion.service /etc/systemd/system/
  ```
- [ ] Reload systemd
  ```bash
  sudo systemctl daemon-reload
  ```
- [ ] Enable service for auto-start
  ```bash
  sudo systemctl enable blockchain-ingestion.service
  ```
- [ ] Start service
  ```bash
  sudo systemctl start blockchain-ingestion.service
  ```
- [ ] Verify service status
  ```bash
  sudo systemctl status blockchain-ingestion.service
  ```
  Expected: Active (running)

### Automated Backups

- [ ] Edit root crontab
  ```bash
  sudo crontab -e
  ```
- [ ] Add daily backup job
  ```
  0 2 * * * /opt/blockchain-ingestion/scripts/backup-clickhouse.sh >> /var/log/blockchain-backup.log 2>&1
  ```
- [ ] Test backup manually
  ```bash
  ./scripts/backup-clickhouse.sh
  ```
- [ ] Verify backup created
  ```bash
  ls -lh /var/backups/blockchain-ingestion/
  ```

### Monitoring and Alerts

- [ ] Edit root crontab
  ```bash
  sudo crontab -e
  ```
- [ ] Add monitoring job
  ```
  */5 * * * * /opt/blockchain-ingestion/scripts/monitor-and-alert.sh >> /var/log/blockchain-monitor.log 2>&1
  ```
- [ ] Test monitoring script
  ```bash
  ./scripts/monitor-and-alert.sh
  ```
- [ ] Optional: Configure Slack webhook
  ```bash
  echo "SLACK_WEBHOOK_URL=https://hooks.slack.com/..." >> .env
  ```

## Data Collection

### Start Collection

Choose one method:

**Option 1: Web Dashboard**
- [ ] Access dashboard: `http://<SERVER_IP>:3001`
- [ ] Click "Start Collection" button
- [ ] Verify "Status: Collecting" displayed

**Option 2: CLI**
- [ ] Start via management script
  ```bash
  ./scripts/manage.sh start-collection
  ```
- [ ] Verify collection started
  ```bash
  ./scripts/manage.sh collection-status
  ```

**Option 3: Direct API**
- [ ] Start via curl
  ```bash
  curl -X POST http://localhost:8000/start
  ```

### Verify Data Ingestion

- [ ] Wait 1-2 minutes for data collection
- [ ] Check Bitcoin blocks
  ```bash
  docker exec blockchain_clickhouse_prod clickhouse-client --password='YOUR_PASSWORD' --query="SELECT count() FROM blockchain_data.bitcoin_blocks"
  ```
  Expected: Non-zero count
- [ ] Check Solana blocks
  ```bash
  docker exec blockchain_clickhouse_prod clickhouse-client --password='YOUR_PASSWORD' --query="SELECT count() FROM blockchain_data.solana_blocks"
  ```
  Expected: Non-zero count
- [ ] Check collection metrics
  ```bash
  docker exec blockchain_clickhouse_prod clickhouse-client --password='YOUR_PASSWORD' --query="SELECT * FROM blockchain_data.collection_metrics ORDER BY metric_time DESC LIMIT 5"
  ```

## Testing

### Functional Tests

- [ ] Stop collection via Web UI
  - Verify status changes to "Stopped"
- [ ] Start collection via Web UI
  - Verify status changes to "Collecting"
- [ ] Stop collection via CLI
  ```bash
  ./scripts/manage.sh stop-collection
  ```
- [ ] Start collection via CLI
  ```bash
  ./scripts/manage.sh start-collection
  ```
- [ ] View logs
  ```bash
  ./scripts/manage.sh logs collector
  ```

### Health Check

- [ ] Run comprehensive health check
  ```bash
  ./scripts/health-check.sh
  ```
  Expected: All checks passed

### Auto-Restart Test

- [ ] Note current uptime
  ```bash
  docker ps --format "{{.Names}}: {{.Status}}"
  ```
- [ ] Reboot server
  ```bash
  sudo reboot
  ```
- [ ] Wait 2 minutes, reconnect
  ```bash
  ssh typeless_sandbox
  ```
- [ ] Verify services auto-started
  ```bash
  cd /opt/blockchain-ingestion
  docker compose -f docker-compose.production.yml ps
  ```
  Expected: All containers running
- [ ] Verify systemd service running
  ```bash
  sudo systemctl status blockchain-ingestion
  ```
  Expected: Active (running)
- [ ] Verify collection status
  ```bash
  curl http://localhost:8000/status
  ```

### Performance Test

- [ ] Monitor resource usage for 5 minutes
  ```bash
  docker stats
  ```
- [ ] Check disk I/O
  ```bash
  iostat -x 1 10
  ```
- [ ] Verify collection rate reasonable
  ```bash
  ./scripts/manage.sh stats
  ```

## Security

### Access Control

- [ ] Dashboard accessible only to authorized users
- [ ] Consider setting up reverse proxy with authentication
- [ ] Firewall rules configured (if applicable)
  ```bash
  sudo ufw status
  ```

### Credentials

- [ ] `.env` file has secure permissions
  ```bash
  chmod 600 /opt/blockchain-ingestion/.env
  ```
- [ ] Strong ClickHouse password in use
- [ ] No credentials in git history
- [ ] `.env.production` in `.gitignore`

### Updates

- [ ] System packages up to date
  ```bash
  sudo apt update && sudo apt upgrade -y
  ```
- [ ] Docker up to date
  ```bash
  docker --version
  ```

## Documentation

### Record Information

Document the following for reference:

- [ ] Server IP address: `_________________`
- [ ] ClickHouse port: `_________________`
- [ ] Dashboard URL: `http://_________________:3001`
- [ ] API URL: `http://_________________:8000`
- [ ] Backup schedule: Daily at 2 AM
- [ ] Monitoring frequency: Every 5 minutes
- [ ] ClickHouse password stored securely
- [ ] Slack webhook URL (if configured): `_________________`

### Team Communication

- [ ] Notify team of deployment
- [ ] Share dashboard URL
- [ ] Document any customizations made
- [ ] Share management commands reference

## Final Verification

### 24-Hour Check

After 24 hours of operation:

- [ ] Service still running
  ```bash
  sudo systemctl status blockchain-ingestion
  ```
- [ ] Data continuously collected
  ```bash
  docker exec blockchain_clickhouse_prod clickhouse-client --password='YOUR_PASSWORD' --query="SELECT count(), max(metric_time) FROM blockchain_data.collection_metrics"
  ```
- [ ] No errors in logs
  ```bash
  ./scripts/manage.sh logs | grep -i error
  ```
- [ ] Health check passing
  ```bash
  ./scripts/health-check.sh
  ```
- [ ] Disk usage acceptable
  ```bash
  df -h /var/lib/blockchain-data
  ```
- [ ] Backup created successfully
  ```bash
  ls -lt /var/backups/blockchain-ingestion/ | head -2
  ```
- [ ] Monitoring alerts working (if configured)

## Rollback Plan

If issues occur:

- [ ] Backup procedure documented
- [ ] Rollback steps understood:
  1. Stop services: `docker compose -f docker-compose.production.yml down`
  2. Restore previous version
  3. Restart services
- [ ] Contact information for support

## Sign-Off

Deployment completed by: `_________________`

Date: `_________________`

All checklist items verified: [ ] Yes / [ ] No

Notes or issues encountered:
```
_________________________________________________
_________________________________________________
_________________________________________________
```

---

For detailed information, see [DEPLOYMENT.md](DEPLOYMENT.md)
