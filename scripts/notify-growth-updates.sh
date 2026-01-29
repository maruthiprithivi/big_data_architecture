#!/bin/bash
# Simple notification script to check monitoring and display updates
# You can run this manually or set it up in a cron job

OUTPUT_FILE="/private/tmp/claude/-Users-maruthi-oasis-big-data-architecture/tasks/b022847.output"
REPORT_FILE="data_growth_report_20260120_030308.log"

# Check if monitoring is running
if ! pgrep -f "monitor-data-growth.sh" > /dev/null; then
    echo "WARNING: Monitoring script is not running!"
    exit 1
fi

# Get the last hourly check from the output
echo "============================================"
echo "Data Growth Monitoring Update"
echo "Time: $(date)"
echo "============================================"
echo ""

# Display the last check
if [ -f "$OUTPUT_FILE" ]; then
    # Get the last "HOURLY CHECK" section
    last_check=$(grep -n "HOURLY CHECK" "$OUTPUT_FILE" | tail -1 | cut -d: -f1)
    if [ ! -z "$last_check" ]; then
        tail -n +$last_check "$OUTPUT_FILE" | head -50
    else
        echo "No hourly checks completed yet. Still on baseline..."
        tail -20 "$OUTPUT_FILE"
    fi
else
    echo "Monitoring output file not found"
fi

echo ""
echo "============================================"
echo "To see full output: tail -f $OUTPUT_FILE"
echo "To see report: cat $REPORT_FILE"
echo "============================================"
