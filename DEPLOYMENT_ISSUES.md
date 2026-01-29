# Deployment Issues and Resolutions

This document records all issues encountered during the Hetzner production deployment, their root causes, and solutions. Use this as a checklist for future deployments.

---

## Issue 1: SSH Configuration Missing

**Error:**
```
ssh: Could not resolve hostname typeless_sandbox: nodename nor servname provided, or not known
```

**Root Cause:**
- No SSH config entry for the Hetzner server
- The deployment script expects a hostname alias "typeless_sandbox"

**Solution:**
Added SSH config entry to `~/.ssh/config`:
```
Host typeless_sandbox
  HostName 37.27.131.209
  User maruthi
  ServerAliveInterval 60
  ServerAliveCountMax 3
```

**Prevention:**
- Always set up SSH config before running deployment scripts
- Document SSH setup as a prerequisite in deployment documentation

---

## Issue 2: Permission Denied for System Directories

**Error:**
```
mkdir: cannot create directory '/opt/blockchain-ingestion': Permission denied
mkdir: cannot create directory '/var/lib/blockchain-data': Permission denied
mkdir: cannot create directory '/var/backups/blockchain-ingestion': Permission denied
```

**Root Cause:**
- Non-root user (maruthi) doesn't have permission to create directories in system locations
- Deployment script assumed root user or didn't use sudo

**Solution:**
Modified `scripts/deploy-to-hetzner.sh` line 52:
```bash
# OLD:
ssh "$REMOTE_USER@$REMOTE_HOST" "mkdir -p $REMOTE_DIR $DATA_DIR/clickhouse $DATA_DIR/collector-state $BACKUP_DIR"

# NEW:
ssh "$REMOTE_USER@$REMOTE_HOST" "sudo mkdir -p $REMOTE_DIR $DATA_DIR/clickhouse $DATA_DIR/collector-state $BACKUP_DIR && sudo chown -R \$USER:\$USER $REMOTE_DIR $DATA_DIR $BACKUP_DIR"
```

**Prevention:**
- Deployment scripts should use sudo for system directory operations
- Verify user has passwordless sudo configured
- Test with `ssh <host> "sudo -n true"` before deployment

---

## Issue 3: Port Conflicts with Existing Services

**Error:**
```
Error response from daemon: failed to set up container networking: driver failed programming external connectivity on endpoint blockchain_clickhouse_prod: Bind for 0.0.0.0:9001 failed: port is already allocated
```

**Root Cause:**
- Server had multiple existing deployments using standard ports:
  - Port 9001: Old blockchain ClickHouse container
  - Port 8000: Agentic investor backend
  - Port 3000: Agentic investor UI
  - Port 8123: Control Zero ClickHouse
  - Port 9000: Control Zero ClickHouse

**Solution:**
Modified `docker-compose.production.yml` to use alternative ports:
- ClickHouse HTTP: 8126 (instead of 8123)
- ClickHouse Native: 9002 (instead of 9001)
- Collector API: 8010 (instead of 8000)
- Dashboard: 3001 (already different from 3000)

**Prevention:**
- Always check for existing services before deployment: `docker ps -a`
- Use the `detect-ports.sh` script (already implemented)
- Consider using a port range reservation strategy
- Document all port allocations on the server
- Consider stopping old deployments if they're no longer needed

---

## Issue 4: CLICKHOUSE_PORT Environment Variable Confusion

**Error:**
```
{"status":"unhealthy","error":"HTTPConnectionPool(host='clickhouse', port=8126): Failed to establish a new connection: [Errno 111] Connection refused"}
```

**Root Cause:**
- The `CLICKHOUSE_PORT` environment variable was being used for two different purposes:
  1. External port mapping in docker-compose.yml (host port)
  2. Internal connection from collector to ClickHouse (container port)
- The deployment script set `CLICKHOUSE_PORT=8126` (external port)
- But collector containers need to use port 8123 (ClickHouse's internal port)

**Solution:**
Modified `docker-compose.production.yml` to explicitly override `CLICKHOUSE_PORT` for internal services:

```yaml
collector:
  environment:
    - CLICKHOUSE_PORT=8123  # Override to use internal container port

dashboard:
  environment:
    - CLICKHOUSE_PORT=8123  # Internal container port
```

**Prevention:**
- Use separate environment variables for external vs internal configurations
- Example: `CLICKHOUSE_EXTERNAL_PORT` and `CLICKHOUSE_INTERNAL_PORT`
- Document the difference between host ports and container ports
- Consider using service discovery instead of hard-coded ports

---

## Issue 5: ClickHouse Alpine Image Password Configuration

**Error:**
```
Code: 516. DB::Exception: default: Authentication failed: password is incorrect
```

**Root Cause:**
- The ClickHouse Alpine image (`clickhouse/clickhouse-server:24.1.8-alpine`) does not automatically configure password authentication from the `CLICKHOUSE_PASSWORD` environment variable
- Standard ClickHouse images may handle this differently

**Current Status:**
- ClickHouse is accessible without password authentication
- This is a security issue for production deployments
- The collector and dashboard are working because they also don't require passwords

**Temporary Workaround:**
- Services are functional without password authentication
- Communication is limited to internal Docker network

**Proper Solution (NOT YET IMPLEMENTED):**
Two options:

1. **Use standard ClickHouse image instead of Alpine:**
   ```yaml
   clickhouse:
     image: clickhouse/clickhouse-server:24.1.8  # Remove -alpine
   ```

2. **Configure password manually with users.xml:**
   Create a `clickhouse-config/users.xml` file:
   ```xml
   <users>
     <default>
       <password_sha256_hex>SHA256_HASH_HERE</password_sha256_hex>
       <networks>
         <ip>::/0</ip>
       </networks>
     </default>
   </users>
   ```

   Mount it in docker-compose.yml:
   ```yaml
   volumes:
     - ./clickhouse-config/users.xml:/etc/clickhouse-server/users.d/users.xml
   ```

**Prevention:**
- Test password authentication immediately after deployment
- Use official ClickHouse image (non-Alpine) if environment variable configuration is needed
- Consider using ClickHouse secrets management
- Add password authentication test to health-check.sh script

**Action Required:**
This issue needs to be fixed before using the deployment in a production environment with external access.

---

## Issue 6: Container Restart Didn't Pick Up Environment Changes

**Observation:**
After updating the `.env` file on the remote server, running `docker compose restart` didn't pick up the new environment variables.

**Root Cause:**
- Docker containers capture environment variables at creation time
- `restart` command doesn't recreate containers with new environment variables
- Environment variables are baked into the container at creation

**Solution:**
Full down/up cycle required:
```bash
docker compose -f docker-compose.production.yml down
docker compose -f docker-compose.production.yml up -d
```

Or use recreate:
```bash
docker compose -f docker-compose.production.yml up -d --force-recreate
```

**Prevention:**
- Use `down` then `up` when environment variables change
- Use `--force-recreate` flag with `up` command
- Document this behavior in operational procedures
- Consider using Docker secrets or config files instead of environment variables

---

## Additional Issues Found

### Network Timing Issue
After bringing containers down and up quickly, sometimes the ClickHouse health check fails temporarily. Solution: Wait 10-15 seconds for ClickHouse to fully start before starting dependent services.

### Build Time
Initial deployment took longer than expected due to building both collector and dashboard images on the remote server. Consider:
- Pre-building images locally and pushing to a registry
- Using Docker BuildKit for faster builds
- Caching layers appropriately

---

## Deployment Checklist (Based on Issues)

Before deploying:
- [ ] Set up SSH config with correct hostname and user
- [ ] Verify user has passwordless sudo access
- [ ] Check existing container ports: `docker ps -a`
- [ ] Run port detection script
- [ ] Review and update `.env.production` if needed
- [ ] Ensure deployment scripts are executable

During deployment:
- [ ] Monitor for port conflicts
- [ ] Verify environment variables in containers
- [ ] Wait for ClickHouse health check before testing
- [ ] Test password authentication immediately

After deployment:
- [ ] Verify all containers running: `docker compose ps`
- [ ] Test API health endpoint
- [ ] Test database connectivity with password
- [ ] Start data collection
- [ ] Verify data ingestion after 1-2 minutes
- [ ] Check systemd service status
- [ ] Verify cron jobs are configured
- [ ] Test backup script manually

---

## Modified Files Summary

Files modified to resolve deployment issues:

1. **scripts/deploy-to-hetzner.sh**
   - Added sudo for directory creation
   - Added chown to fix permissions

2. **docker-compose.production.yml**
   - Changed port 9001 → 9002 for ClickHouse native
   - Changed port 8000 → 8010 for collector API
   - Added explicit CLICKHOUSE_PORT=8123 override for collector
   - Added explicit CLICKHOUSE_PORT=8123 override for dashboard

3. **~/.ssh/config**
   - Added typeless_sandbox host entry

---

## Recommended Improvements

Based on issues encountered, consider these improvements:

1. **Port Management:**
   - Create a port allocation document for the server
   - Use environment variables for all port mappings
   - Implement port conflict detection in deployment script

2. **Security:**
   - Fix ClickHouse password authentication
   - Use Docker secrets for sensitive data
   - Implement network isolation between projects

3. **Deployment Script:**
   - Add pre-flight checks (SSH, sudo, ports)
   - Add rollback capability
   - Add dry-run mode
   - Improve error messages

4. **Monitoring:**
   - Add alerting for deployment failures
   - Monitor port conflicts automatically
   - Track deployment success/failure metrics

5. **Documentation:**
   - Keep this issues document updated
   - Document all port allocations
   - Create runbooks for common issues

---

## Current Production State

**Status:** Deployed and Running

**Known Issues:**
- ClickHouse password authentication not configured (security risk)
- Multiple old deployments consuming resources

**Working Components:**
- All containers running and healthy
- Data collection active (Bitcoin and Solana)
- Dashboard accessible
- API functional
- Systemd service configured
- Automated backups configured (daily at 2 AM)
- Monitoring configured (every 5 minutes)

**Action Items:**
1. Fix ClickHouse password authentication
2. Consider cleaning up old deployments
3. Test backup and restore procedures
4. Set up monitoring alerts
5. Document password in secure location (if implemented)
