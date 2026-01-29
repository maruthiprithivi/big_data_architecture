# Production Deployment Guide

This guide covers deploying the blockchain data ingestion service to a production server (Hetzner typeless_sandbox instance) as a continuously running service.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Server Requirements](#server-requirements)
- [Initial Setup](#initial-setup)
- [Deployment Process](#deployment-process)
- [Post-Deployment Configuration](#post-deployment-configuration)
- [Management Commands](#management-commands)
- [Monitoring and Maintenance](#monitoring-and-maintenance)
- [Troubleshooting](#troubleshooting)
- [Backup and Restore](#backup-and-restore)
- [Updates](#updates)

## Prerequisites

### Local Machine

- SSH access to the remote server
- Git installed
- rsync installed
- SSH config entry for `typeless_sandbox` or set `REMOTE_USER` environment variable

### SSH Configuration

Add to `~/.ssh/config`:

```
Host typeless_sandbox
    HostName <YOUR_SERVER_IP>
    User root
    IdentityFile ~/.ssh/your_key
    Port 22
```

## Server Requirements

### Minimum Specifications

- OS: Ubuntu 20.04+ or Debian 11+
- RAM: 4GB minimum, 8GB recommended
- Disk: 100GB minimum available space
- CPU: 2 cores minimum
- Docker: 20.10+
- Docker Compose: v2.0+

### Port Requirements

The deployment script automatically detects available ports. Default ports:
- ClickHouse HTTP: 8123 (or 8125, 8126 if conflict)
- ClickHouse Native: 9001
- Collector API: 8000
- Dashboard: 3001

### Install Docker on Server

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Install Docker Compose v2
sudo apt install docker-compose-plugin -y

# Verify installation
docker --version
docker compose version
```

## Initial Setup

### 1. Clone Repository (Local)

```bash
cd ~/projects
git clone https://github.com/maruthiprithivi/big_data_architecture.git
cd big_data_architecture
```

### 2. Configure Production Environment

Review and customize `.env.production`:

```bash
# Edit production settings
nano .env.production
```

Key settings to review:
- `CLICKHOUSE_PASSWORD`: Set a strong password
- `MAX_DATA_SIZE_GB`: Adjust based on disk capacity
- `ENABLE_TIME_LIMIT`: Set to `false` for continuous operation
- RPC URLs for Bitcoin, Solana (use your own if available)

### 3. Test SSH Connectivity

```bash
ssh typeless_sandbox "echo 'Connection successful'"
```

## Deployment Process

### Automated Deployment

Run the automated deployment script:

```bash
./scripts/deploy-to-hetzner.sh
```

This script will:
1. Check SSH connectivity
2. Detect available ClickHouse port
3. Create remote directories
4. Sync project files
5. Deploy .env.production as .env
6. Start Docker services
7. Display access URLs

### Manual Deployment (Alternative)

If you prefer manual deployment:

```bash
# 1. Create directories on remote server
ssh typeless_sandbox "mkdir -p /opt/blockchain-ingestion /var/lib/blockchain-data /var/backups/blockchain-ingestion"

# 2. Sync files
rsync -avz --exclude 'data/' --exclude 'node_modules/' --exclude '.git/' \
  . root@typeless_sandbox:/opt/blockchain-ingestion/

# 3. Deploy environment file
scp .env.production root@typeless_sandbox:/opt/blockchain-ingestion/.env

# 4. Start services
ssh typeless_sandbox "cd /opt/blockchain-ingestion && docker compose -f docker-compose.production.yml up -d"
```

## Post-Deployment Configuration

### 1. Install systemd Service

Enable automatic service restart on server reboot:

```bash
# SSH to server
ssh typeless_sandbox

# Navigate to installation directory
cd /opt/blockchain-ingestion

# Copy service file
sudo cp scripts/blockchain-ingestion.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable service
sudo systemctl enable blockchain-ingestion.service

# Start service
sudo systemctl start blockchain-ingestion.service

# Check status
sudo systemctl status blockchain-ingestion.service
```

### 2. Configure Automated Backups

Set up daily backups via cron:

```bash
# Edit crontab
sudo crontab -e

# Add backup job (runs daily at 2 AM)
0 2 * * * /opt/blockchain-ingestion/scripts/backup-clickhouse.sh >> /var/log/blockchain-backup.log 2>&1
```

### 3. Configure Monitoring

Set up continuous health monitoring:

```bash
# Edit crontab
sudo crontab -e

# Add monitoring job (runs every 5 minutes)
*/5 * * * * /opt/blockchain-ingestion/scripts/monitor-and-alert.sh >> /var/log/blockchain-monitor.log 2>&1
```

Optional: Configure Slack alerts by setting `SLACK_WEBHOOK_URL`:

```bash
# Add to .env
echo "SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL" >> /opt/blockchain-ingestion/.env
```

## Management Commands

### Using the CLI Management Script

The `manage.sh` script provides convenient control:

```bash
# Service control
./scripts/manage.sh start              # Start all services
./scripts/manage.sh stop               # Stop all services
./scripts/manage.sh restart            # Restart all services
./scripts/manage.sh status             # Show service status

# Collection control
./scripts/manage.sh start-collection   # Start data collection
./scripts/manage.sh stop-collection    # Stop data collection
./scripts/manage.sh collection-status  # Show collection status

# Monitoring
./scripts/manage.sh health             # Check service health
./scripts/manage.sh stats              # Show collection statistics
./scripts/manage.sh logs               # View all logs
./scripts/manage.sh logs collector     # View collector logs only

# Maintenance
./scripts/manage.sh backup             # Create backup
```

### Using systemd

```bash
# Service control
sudo systemctl start blockchain-ingestion
sudo systemctl stop blockchain-ingestion
sudo systemctl restart blockchain-ingestion
sudo systemctl status blockchain-ingestion

# View logs
sudo journalctl -u blockchain-ingestion -f
```

### Using Web Dashboard

Access the dashboard at: `http://<SERVER_IP>:3001`

Features:
- Start/Stop collection
- View real-time metrics
- Monitor table sizes
- View recent blocks/transactions

## Monitoring and Maintenance

### Health Checks

Run comprehensive health check:

```bash
./scripts/health-check.sh
```

Checks performed:
- Docker service status
- Container status (ClickHouse, Collector, Dashboard)
- API health
- Collection status
- Database connectivity
- Table statistics
- Disk space usage

### View Logs

```bash
# All services
./scripts/manage.sh logs

# Specific service
./scripts/manage.sh logs collector
./scripts/manage.sh logs clickhouse
./scripts/manage.sh logs dashboard

# Using docker compose directly
docker compose -f docker-compose.production.yml logs -f --tail=100 collector
```

### Monitor Resource Usage

```bash
# Container resource usage
docker stats blockchain_clickhouse_prod blockchain_collector_prod blockchain_dashboard_prod

# Disk usage
df -h /var/lib/blockchain-data

# ClickHouse database size
docker exec blockchain_clickhouse_prod clickhouse-client \
  --password='YOUR_PASSWORD' \
  --query="SELECT database, formatReadableSize(sum(bytes_on_disk)) AS size FROM system.parts WHERE active GROUP BY database"
```

## Troubleshooting

### Services Won't Start

```bash
# Check Docker daemon
sudo systemctl status docker

# Check container logs
docker compose -f docker-compose.production.yml logs

# Check port conflicts
ss -tlnp | grep -E '8123|8000|3001|9001'

# Restart services
docker compose -f docker-compose.production.yml down
docker compose -f docker-compose.production.yml up -d
```

### Collection Not Starting

```bash
# Check collector status
curl http://localhost:8000/health

# View collector logs
docker logs blockchain_collector_prod -f

# Manually start collection
curl -X POST http://localhost:8000/start

# Check safety limits
# Review MAX_DATA_SIZE_GB and ENABLE_TIME_LIMIT in .env
```

### ClickHouse Connection Issues

```bash
# Test ClickHouse connectivity
docker exec blockchain_clickhouse_prod clickhouse-client \
  --password='YOUR_PASSWORD' \
  --query="SELECT 1"

# Check ClickHouse logs
docker logs blockchain_clickhouse_prod

# Verify ClickHouse is listening
docker exec blockchain_clickhouse_prod ss -tlnp | grep clickhouse
```

### Disk Space Issues

```bash
# Check disk usage
df -h

# Clean old Docker images
docker system prune -a

# Clean old backups
find /var/backups/blockchain-ingestion -type d -mtime +7 -exec rm -rf {} +

# Check ClickHouse data size
docker exec blockchain_clickhouse_prod clickhouse-client \
  --password='YOUR_PASSWORD' \
  --query="SELECT table, formatReadableSize(sum(bytes_on_disk)) FROM system.parts WHERE active GROUP BY table"
```

### Performance Issues

```bash
# Check system resources
htop
free -h
iostat -x 1

# Check Docker container stats
docker stats

# Review collection interval
# Consider increasing COLLECTION_INTERVAL_SECONDS in .env

# Check ClickHouse query performance
docker exec blockchain_clickhouse_prod clickhouse-client \
  --password='YOUR_PASSWORD' \
  --query="SELECT query, query_duration_ms FROM system.query_log ORDER BY query_duration_ms DESC LIMIT 10"
```

## Backup and Restore

### Create Backup

```bash
# Automated backup
./scripts/backup-clickhouse.sh

# Manual backup
docker exec blockchain_clickhouse_prod clickhouse-client \
  --password='YOUR_PASSWORD' \
  --query="BACKUP DATABASE blockchain_data TO Disk('default', '/var/lib/clickhouse/backup/')"
```

Backups are stored in: `/var/backups/blockchain-ingestion/YYYYMMDD-HHMMSS/`

### Restore from Backup

```bash
# 1. Stop collection
curl -X POST http://localhost:8000/stop

# 2. Restore using native format
BACKUP_DATE="20260120-140000"  # Replace with your backup timestamp

docker exec blockchain_clickhouse_prod clickhouse-client \
  --password='YOUR_PASSWORD' \
  --query="TRUNCATE TABLE blockchain_data.bitcoin_blocks"

# Restore data from backup directory
# (Implementation depends on backup format)

# 3. Restart collection
curl -X POST http://localhost:8000/start
```

## Updates

### Zero-Downtime Update

Use the update script for automated updates:

```bash
# From local machine
./scripts/update.sh

# Skip pre-update backup (faster, but risky)
./scripts/update.sh -s
```

The update process:
1. Creates backup (optional)
2. Stops data collection
3. Pulls latest code
4. Rebuilds containers
5. Restarts services
6. Resumes collection
7. Verifies health

### Manual Update

```bash
# SSH to server
ssh typeless_sandbox
cd /opt/blockchain-ingestion

# Stop collection
curl -X POST http://localhost:8000/stop

# Pull updates
git pull origin main

# Rebuild and restart
docker compose -f docker-compose.production.yml build
docker compose -f docker-compose.production.yml up -d

# Resume collection
curl -X POST http://localhost:8000/start
```

## Security Considerations

1. **Change Default Passwords**: Update `CLICKHOUSE_PASSWORD` in `.env.production`
2. **Firewall Rules**: Restrict access to necessary ports only
3. **SSH Keys**: Use SSH key authentication, disable password auth
4. **Regular Updates**: Keep system and Docker packages updated
5. **Backup Encryption**: Consider encrypting backups if they contain sensitive data
6. **Network Security**: Use VPN or firewall rules to restrict dashboard access

## Production Checklist

After deployment, verify:

- [ ] All containers running: `docker ps`
- [ ] Health check passing: `./scripts/health-check.sh`
- [ ] Collection active: Check dashboard or `curl http://localhost:8000/status`
- [ ] systemd service enabled: `systemctl is-enabled blockchain-ingestion`
- [ ] Automated backups configured: `sudo crontab -l`
- [ ] Monitoring configured: `sudo crontab -l`
- [ ] Dashboard accessible: `http://<SERVER_IP>:3001`
- [ ] Data being collected: Query ClickHouse tables
- [ ] Auto-restart tested: Reboot server and verify services come back up

## Support

For issues or questions:
- Review troubleshooting section above
- Check logs: `./scripts/manage.sh logs`
- Run health check: `./scripts/health-check.sh`
- Refer to main README.md for architecture details
