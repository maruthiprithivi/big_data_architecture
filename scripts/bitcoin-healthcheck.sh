#!/bin/bash
# Bitcoin Core Healthcheck Script
# Simple check that doesn't require authentication

# Check if bitcoind is responding on RPC port
nc -z localhost 8332 2>/dev/null
exit $?
