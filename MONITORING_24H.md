# 24-Hour Data Growth Monitoring

**Started:** January 20, 2026 at 03:03:08 UTC
**Duration:** 24 hours (until January 21, 2026 at 03:03:08 UTC)
**Check Interval:** Every 1 hour
**Task ID:** b022847

---

## Baseline Metrics (Starting Point)

As of January 20, 2026 at 03:03:08 UTC:

| Table | Rows | Size (GB) |
|-------|------|-----------|
| Bitcoin Blocks | 3 | 0.000004 |
| Bitcoin Transactions | 75 | 0.000007 |
| Solana Blocks | 188 | 0.000014 |
| Solana Transactions | 9,450 | 0.000601 |
| **Total** | **9,716** | **0.000626** |

---

## What's Being Monitored

The script queries the production ClickHouse database on the Hetzner server every hour and tracks:

1. **Row Counts** - Total number of records in each table
2. **Table Sizes** - Disk space used by each table in GB
3. **Hourly Growth** - Change in rows and size since the last check
4. **Collection Health** - API health status

---

## How to Check Progress

### Option 1: Quick Status Check (Recommended)
```bash
./scripts/check-monitoring-status.sh
```

### Option 2: Watch Live Output
```bash
tail -f /private/tmp/claude/-Users-maruthi-oasis-big-data-architecture/tasks/b022847.output
```

### Option 3: View Report File
The script writes to a local report file with a timestamp:
```bash
cat data_growth_report_20260120_030308.log
```

Or view the latest updates:
```bash
tail -100 data_growth_report_20260120_030308.log
```

---

## Hourly Report Format

Every hour, you'll see a report like this:

```
==========================================
HOURLY CHECK #5 (Hour 5 of 24)
==========================================

Bitcoin Blocks:
  Current:  15 rows, 0.000020 GB
  Growth:   3 rows/hour, 0.000004 GB/hour

Bitcoin Transactions:
  Current:  425 rows, 0.000035 GB
  Growth:   70 rows/hour, 0.000006 GB/hour

Solana Blocks:
  Current:  950 rows, 0.000071 GB
  Growth:   152 rows/hour, 0.000011 GB/hour

Solana Transactions:
  Current:  47,250 rows, 0.003005 GB
  Growth:   7,560 rows/hour, 0.000481 GB/hour

HOURLY SUMMARY:
  Total rows added:     7,785 rows/hour
  Total size increase:  0.000502 GB/hour

Collection Status: Healthy
===========================================
```

---

## Expected Hourly Checks

Based on the 1-hour interval, checks will occur approximately at:

1. 04:03 UTC - Hour 1
2. 05:03 UTC - Hour 2
3. 06:03 UTC - Hour 3
4. 07:03 UTC - Hour 4
5. 08:03 UTC - Hour 5
6. 09:03 UTC - Hour 6
7. 10:03 UTC - Hour 7
8. 11:03 UTC - Hour 8
9. 12:03 UTC - Hour 9
10. 13:03 UTC - Hour 10
11. 14:03 UTC - Hour 11
12. 15:03 UTC - Hour 12
13. 16:03 UTC - Hour 13
14. 17:03 UTC - Hour 14
15. 18:03 UTC - Hour 15
16. 19:03 UTC - Hour 16
17. 20:03 UTC - Hour 17
18. 21:03 UTC - Hour 18
19. 22:03 UTC - Hour 19
20. 23:03 UTC - Hour 20
21. 00:03 UTC - Hour 21
22. 01:03 UTC - Hour 22
23. 02:03 UTC - Hour 23
24. 03:03 UTC - Hour 24 (Final)

---

## Final Report

At the end of 24 hours, the script will generate a comprehensive summary showing:

- Total rows added across all tables
- Total size increase in GB
- Average growth per hour
- Before/after comparison for each table

---

## Monitoring the Monitoring

### Check if the script is still running:
```bash
ps aux | grep monitor-data-growth.sh
```

### Check the task output file size (should grow each hour):
```bash
ls -lh /private/tmp/claude/-Users-maruthi-oasis-big-data-architecture/tasks/b022847.output
```

### Check the report file (should update hourly):
```bash
ls -lh data_growth_report_20260120_030308.log
```

---

## If Something Goes Wrong

### Script stopped unexpectedly:
1. Check the last output:
   ```bash
   tail -100 /private/tmp/claude/-Users-maruthi-oasis-big-data-architecture/tasks/b022847.output
   ```

2. Check if SSH connection is working:
   ```bash
   ssh typeless_sandbox "echo 'Connection OK'"
   ```

3. Restart the monitoring:
   ```bash
   ./scripts/monitor-data-growth.sh
   ```

### No updates appearing:
- The script waits 1 hour between checks, so this is normal
- Check the timestamp of the last update to verify it's progressing

---

## Manual Data Check

To manually check the current state at any time:

```bash
ssh typeless_sandbox "docker exec blockchain_clickhouse_prod clickhouse-client --query='SELECT count() FROM blockchain_data.bitcoin_blocks'"

ssh typeless_sandbox "docker exec blockchain_clickhouse_prod clickhouse-client --query='SELECT count() FROM blockchain_data.solana_blocks'"
```

---

## Files Created

1. **Monitor Script:** `scripts/monitor-data-growth.sh`
2. **Status Checker:** `scripts/check-monitoring-status.sh`
3. **Report File:** `data_growth_report_20260120_030308.log` (will be created in current directory)
4. **Background Output:** `/private/tmp/claude/-Users-maruthi-oasis-big-data-architecture/tasks/b022847.output`

---

## What Happens After 24 Hours

When the monitoring completes:

1. The script will generate a final comprehensive report
2. The background task will exit
3. All data will be saved in the report file
4. You can review the complete 24-hour growth analysis

The report file will remain in your project directory for future reference.

---

## Quick Commands Reference

```bash
# Check status
./scripts/check-monitoring-status.sh

# Watch live
tail -f /private/tmp/claude/-Users-maruthi-oasis-big-data-architecture/tasks/b022847.output

# View report
tail -100 data_growth_report_20260120_030308.log

# Check if running
ps aux | grep monitor-data-growth.sh

# Manual verification
ssh typeless_sandbox "curl -s http://localhost:8010/health | jq"
```

---

## Notification Strategy

Since this is a command-line monitoring script, updates are written to the output file. To get notifications:

**Option 1: Periodic Manual Checks**
- Check the status every few hours using the check-monitoring-status.sh script

**Option 2: Set Up Your Own Alerts**
- Use a cron job or scheduled task to run the status checker
- Parse the output and send notifications via email/Slack/etc.

**Option 3: Watch the File**
- Keep a terminal open with `tail -f` running
- You'll see each hourly update as it happens

---

**Remember:** The monitoring is running in the background and will continue even if you close your terminal. The data is being saved to the report file continuously.
