#!/bin/bash
# Quick script to check monitoring status

OUTPUT_DIR="/private/tmp/claude/-Users-maruthi-oasis-big-data-architecture/tasks"
LATEST_LOG=$(ls -t data_growth_report_*.log 2>/dev/null | head -1)

echo "=========================================="
echo "Data Growth Monitoring Status"
echo "=========================================="
echo ""

# Check if monitoring task is running
if pgrep -f "monitor-data-growth.sh" > /dev/null; then
    echo "Status: RUNNING"
    echo ""
    echo "Latest output from background task:"
    echo "------------------------------------------"
    tail -30 "$OUTPUT_DIR"/*.output 2>/dev/null | tail -30
else
    echo "Status: NOT RUNNING"
fi

echo ""
echo "=========================================="
echo ""

# Show latest log file if it exists
if [ -f "$LATEST_LOG" ]; then
    echo "Latest report file: $LATEST_LOG"
    echo "Lines in report: $(wc -l < "$LATEST_LOG")"
    echo ""
    echo "Last 30 lines of report:"
    echo "------------------------------------------"
    tail -30 "$LATEST_LOG"
else
    echo "No report files found in current directory"
fi

echo ""
echo "=========================================="
echo "To view full output: tail -f /private/tmp/claude/-Users-maruthi-oasis-big-data-architecture/tasks/b022847.output"
echo "To view report file: cat data_growth_report_*.log"
echo "=========================================="
