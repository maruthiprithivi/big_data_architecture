"""
Blockchain Data Ingestion Dashboard
Real-time monitoring and control interface

=== EDUCATIONAL OVERVIEW ===

This dashboard demonstrates building real-time data visualization applications
using Streamlit, a Python library that turns scripts into web apps.

Key Concepts Demonstrated:
1. Streamlit Framework: Declarative UI with automatic updates
2. REST API Integration: Controlling the collector service via HTTP
3. Real-Time Data Visualization: Charts that update with new data
4. Caching: Using @st.cache_resource for expensive operations
5. Plotly: Interactive charting library for data visualization

Streamlit's Execution Model:
Unlike traditional web frameworks (Flask, Django), Streamlit re-runs the ENTIRE
script from top to bottom on each user interaction. This makes development simple
but requires understanding:
- @st.cache_resource: Cache expensive resources (database connections)
- @st.cache_data: Cache data that doesn't change frequently
- st.session_state: Persist state across reruns

This app auto-refreshes every 5 seconds to show real-time collection progress.
"""

import streamlit as st
import clickhouse_connect
import requests
import os
from datetime import datetime
import time
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# EDUCATIONAL NOTE - Streamlit Page Configuration:
# set_page_config() MUST be the first Streamlit command in your script.
# It configures browser tab title, favicon, and layout options.
# layout="wide" uses the full browser width instead of a centered column.
st.set_page_config(
    page_title="Blockchain Data Ingestion Dashboard",
    page_icon="⛓️",
    layout="wide"
)


def calculate_time_remaining(started_at_str, max_minutes):
    """
    Calculate time remaining before collection safety limit is reached.

    Args:
        started_at_str: ISO format datetime string when collection started
        max_minutes: Maximum collection time in minutes

    Returns:
        tuple: (remaining_seconds: int, percentage_used: float, color: str)
    """
    if not started_at_str:
        return 0, 0, 'normal'

    started_at = datetime.fromisoformat(started_at_str)
    elapsed = datetime.now() - started_at
    max_seconds = max_minutes * 60
    elapsed_seconds = int(elapsed.total_seconds())
    remaining_seconds = max(0, max_seconds - elapsed_seconds)
    percentage_used = (elapsed_seconds / max_seconds * 100) if max_seconds > 0 else 0

    # Color coding based on time remaining
    if remaining_seconds > 300:  # > 5 minutes
        color = 'normal'
    elif remaining_seconds > 120:  # > 2 minutes
        color = 'warning'
    else:  # < 2 minutes or stopped
        color = 'critical'

    return remaining_seconds, percentage_used, color


# EDUCATIONAL NOTE - Streamlit Caching:
#
# @st.cache_resource is for objects that should be shared across all users
# and persist across reruns (like database connections, ML models).
#
# How it works:
# 1. First call: Creates the client and caches it
# 2. Subsequent calls: Returns the cached client
# 3. Never re-creates unless the function code changes
#
# Without caching, each rerun (every 5 seconds!) would create a new database
# connection, eventually exhausting connection limits and slowing down the app.
#
# Compare with @st.cache_data: For caching serializable data (DataFrames,
# strings, numbers). Automatically invalidates based on function inputs.
@st.cache_resource
def get_clickhouse_client():
    """
    Create and cache a ClickHouse client connection.

    The @st.cache_resource decorator ensures we reuse the same connection
    across all reruns and users, preventing connection pool exhaustion.
    """
    return clickhouse_connect.get_client(
        host=os.getenv('CLICKHOUSE_HOST', 'clickhouse'),
        port=int(os.getenv('CLICKHOUSE_PORT', 8123)),
        username=os.getenv('CLICKHOUSE_USER', 'default'),
        password=os.getenv('CLICKHOUSE_PASSWORD', ''),
        database=os.getenv('CLICKHOUSE_DB', 'blockchain_data')
    )


# EDUCATIONAL NOTE - Service Communication:
# The dashboard runs in a separate container from the collector.
# In Docker Compose, services can communicate using service names as hostnames.
# "collector:8000" resolves to the collector container's IP address.
COLLECTOR_URL = "http://collector:8000"


def get_collector_status():
    """
    Get collector status from the FastAPI service.

    EDUCATIONAL NOTE - REST API Client:
    The dashboard acts as a client to the collector's REST API.
    - GET /status: Retrieves current collection state
    - POST /start: Triggers collection to begin
    - POST /stop: Triggers collection to stop

    We use the requests library for synchronous HTTP calls.
    Timeout of 5 seconds prevents the dashboard from hanging if collector is slow.
    """
    try:
        response = requests.get(f"{COLLECTOR_URL}/status", timeout=5)
        return response.json()
    except Exception as e:
        st.error(f"Error connecting to collector: {e}")
        return None


def start_collection():
    """Start data collection via the collector API."""
    try:
        response = requests.post(f"{COLLECTOR_URL}/start", timeout=5)
        return response.json()
    except Exception as e:
        st.error(f"Error starting collection: {e}")
        return None


def stop_collection():
    """Stop data collection via the collector API."""
    try:
        response = requests.post(f"{COLLECTOR_URL}/stop", timeout=5)
        return response.json()
    except Exception as e:
        st.error(f"Error stopping collection: {e}")
        return None


# =============================================================================
# DASHBOARD LAYOUT
# =============================================================================

# EDUCATIONAL NOTE - Streamlit Components:
# Streamlit provides declarative UI components:
# - st.title(), st.header(), st.subheader(): Text headings
# - st.columns(): Create horizontal layouts
# - st.metric(): Display KPI-style numbers with optional delta
# - st.dataframe(): Interactive data tables
# - st.plotly_chart(): Plotly visualizations
# - st.button(): Clickable buttons that trigger actions

st.title("⛓️ Blockchain Data Ingestion Dashboard")
st.markdown("Real-time monitoring of blockchain data collection from Bitcoin and Solana")

# Control buttons - arranged in columns for horizontal layout
col1, col2, col3 = st.columns([1, 1, 4])

with col1:
    # EDUCATIONAL NOTE - Button Actions:
    # When a button is clicked, Streamlit reruns the entire script.
    # The if-block only executes on the click that triggered the rerun.
    # st.rerun() forces an immediate refresh to show updated state.
    if st.button("▶️ Start Collection", type="primary", use_container_width=True):
        result = start_collection()
        if result:
            st.success("Collection started!")
            time.sleep(1)
            st.rerun()

with col2:
    if st.button("⏹️ Stop Collection", type="secondary", use_container_width=True):
        result = stop_collection()
        if result:
            st.success("Collection stopped!")
            time.sleep(1)
            st.rerun()

st.divider()

# Get data from ClickHouse and collector API
client = get_clickhouse_client()
status = get_collector_status()

# =============================================================================
# STATUS SECTION
# =============================================================================

st.subheader("📊 Collection Status")

if status:
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        is_running = status.get('is_running', False)
        status_text = "🟢 Running" if is_running else "🔴 Stopped"
        st.metric("Status", status_text)

    with col2:
        total_records = status.get('total_records', 0)
        st.metric("Total Records", f"{total_records:,}")

    with col3:
        # Convert bytes to human-readable format
        total_size = status.get('total_size_bytes', 0)
        size_mb = total_size / (1024 * 1024)
        size_gb = total_size / (1024 * 1024 * 1024)
        size_display = f"{size_gb:.2f} GB" if size_gb >= 1 else f"{size_mb:.2f} MB"
        st.metric("Data Size", size_display)

    with col4:
        max_time_min = int(os.getenv('MAX_COLLECTION_TIME_MINUTES', 10))

        if is_running and status.get('started_at'):
            # Calculate time remaining until collection auto-stops
            remaining_seconds, percentage_used, color_code = calculate_time_remaining(
                status.get('started_at'), max_time_min
            )

            minutes = remaining_seconds // 60
            seconds = remaining_seconds % 60

            # Display with color coding
            if color_code == 'critical':
                st.error(f"⏱️ {minutes}:{seconds:02d} remaining")
            elif color_code == 'warning':
                st.warning(f"⏱️ {minutes}:{seconds:02d} remaining")
            else:
                st.success(f"⏱️ {minutes}:{seconds:02d} remaining")

            st.caption(f"{percentage_used:.1f}% of collection time used")
            st.progress(min(percentage_used / 100, 1.0))
        else:
            st.metric("Max Collection Time", f"{max_time_min} min")

st.divider()

# =============================================================================
# RECORDS BY SOURCE SECTION
# =============================================================================

st.subheader("📈 Records by Blockchain Source")

try:
    # EDUCATIONAL NOTE - SQL with UNION ALL:
    # We query counts from all 6 tables in a single query using UNION ALL.
    # This is more efficient than making 6 separate queries.
    # The result gives us a breakdown by data type (blocks vs transactions)
    # and blockchain source (Ethereum, Bitcoin, Solana).
    counts_query = """
    -- ETHEREUM DISABLED - Uncomment when Ethereum collection is enabled
    -- SELECT
    --     'Ethereum Blocks' as source, count() as count FROM ethereum_blocks
    -- UNION ALL
    -- SELECT 'Ethereum Transactions' as source, count() as count FROM ethereum_transactions
    -- UNION ALL
    SELECT 'Bitcoin Blocks' as source, count() as count FROM bitcoin_blocks
    UNION ALL
    SELECT 'Bitcoin Transactions' as source, count() as count FROM bitcoin_transactions
    UNION ALL
    SELECT 'Solana Blocks' as source, count() as count FROM solana_blocks
    UNION ALL
    SELECT 'Solana Transactions' as source, count() as count FROM solana_transactions
    ORDER BY
        CASE source
            WHEN 'Bitcoin Blocks' THEN 1
            WHEN 'Bitcoin Transactions' THEN 2
            WHEN 'Solana Blocks' THEN 3
            WHEN 'Solana Transactions' THEN 4
        END
    """

    counts_result = client.query(counts_query)
    counts_df = pd.DataFrame(counts_result.result_rows, columns=['Source', 'Count'])

    # Convert Source to categorical type with explicit order for stability
    # This ensures the DataFrame maintains the correct order and the table respects it
    from pandas.api.types import CategoricalDtype

    source_order = ['Bitcoin Blocks', 'Bitcoin Transactions', 'Solana Blocks', 'Solana Transactions']
    cat_type = CategoricalDtype(categories=source_order, ordered=True)
    counts_df['Source'] = counts_df['Source'].astype(cat_type)
    counts_df = counts_df.sort_values('Source')  # Ensures DataFrame is sorted

    col1, col2 = st.columns([2, 1])

    with col1:
        # EDUCATIONAL NOTE - Plotly Express:
        # px.bar() creates a bar chart with minimal code.
        # Plotly charts are interactive: hover for details, zoom, pan, export.
        # use_container_width=True makes the chart fill the available space.

        # Define fixed colors for consistent visualization
        # Using blockchain brand colors to prevent random color changes
        color_map = {
            'Bitcoin Blocks': '#F7931A',        # Bitcoin orange
            'Bitcoin Transactions': '#FF6B35',   # Lighter orange
            'Solana Blocks': '#14F195',         # Solana green
            'Solana Transactions': '#9945FF'    # Solana purple
        }

        fig = px.bar(
            counts_df,
            x='Source',
            y='Count',
            color='Source',
            color_discrete_map=color_map,  # Explicit color mapping for stability
            title='Record Count by Source',
            category_orders={'Source': ['Bitcoin Blocks', 'Bitcoin Transactions', 'Solana Blocks', 'Solana Transactions']}  # Override Plotly's alphabetical sorting
        )
        fig.update_layout(showlegend=False, height=400)
        st.plotly_chart(fig, use_container_width=True)

    with col2:
        # EDUCATIONAL NOTE - Pandas Styling:
        # .style.format() applies formatting to specific columns.
        # '{:,.0f}' formats numbers with thousands separators, no decimals.
        st.dataframe(
            counts_df.style.format({'Count': '{:,.0f}'}),
            use_container_width=True,
            height=400,
            hide_index=True
        )

except Exception as e:
    st.error(f"Error fetching record counts: {e}")

st.divider()

# # =============================================================================
# # PERFORMANCE METRICS SECTION - COMMENTED OUT
# # =============================================================================
#
# st.subheader("⚡ Collection Performance")
#
# try:
#     # EDUCATIONAL NOTE - Time-Series Data:
#     # We aggregate metrics by minute using toStartOfMinute() for cleaner charts.
#     # The WHERE clause filters to last 10 minutes to show recent performance.
#     # GROUP BY creates one data point per minute per blockchain source.
#     metrics_query = """
#     SELECT
#         source,
#         toStartOfMinute(metric_time) as minute,
#         sum(records_collected) as total_records,
#         avg(collection_duration_ms) as avg_duration_ms,
#         sum(error_count) as errors
#     FROM collection_metrics
#     WHERE metric_time >= now() - INTERVAL 10 MINUTE
#     GROUP BY source, minute
#     ORDER BY minute DESC, source
#     """
#
#     metrics_result = client.query(metrics_query)
#
#     if metrics_result.result_rows:
#         metrics_df = pd.DataFrame(
#             metrics_result.result_rows,
#             columns=['Source', 'Minute', 'Records', 'Avg Duration (ms)', 'Errors']
#         )
#
#         col1, col2 = st.columns(2)
#
#         with col1:
#             # Line chart showing records over time
#             fig = px.line(
#                 metrics_df,
#                 x='Minute',
#                 y='Records',
#                 color='Source',
#                 title='Records Collected Over Time (Last 10 Minutes)'
#             )
#             fig.update_layout(height=350)
#             st.plotly_chart(fig, use_container_width=True)
#
#         with col2:
#             # Bar chart showing average collection duration
#             fig = px.bar(
#                 metrics_df.groupby('Source', sort=False)['Avg Duration (ms)'].mean().reset_index(),
#                 x='Source',
#                 y='Avg Duration (ms)',
#                 color='Source',
#                 title='Average Collection Duration by Source',
#                 category_orders={'Source': ['ethereum', 'bitcoin', 'solana']}  # Maintain stable order
#             )
#             fig.update_layout(showlegend=False, height=350)
#             st.plotly_chart(fig, use_container_width=True)
#
#         # Calculate and display events per second for each blockchain
#         col1, col2, col3 = st.columns(3)
#
#         interval = int(os.getenv('COLLECTION_INTERVAL_SECONDS', 5))
#
#         for idx, source in enumerate(['ethereum', 'bitcoin', 'solana']):
#             source_df = metrics_df[metrics_df['Source'] == source]
#             if not source_df.empty:
#                 # Sum records from last 5 collection cycles
#                 recent_records = source_df.head(5)['Records'].sum()
#                 # Calculate events per second (records / total seconds)
#                 events_per_sec = recent_records / (interval * 5) if interval > 0 else 0
#
#                 with [col1, col2, col3][idx]:
#                     st.metric(
#                         f"{source.capitalize()} Events/sec",
#                         f"{events_per_sec:.2f}"
#                     )
#     else:
#         st.info("No collection metrics available yet. Start collection to see performance data.")
#
# except Exception as e:
#     st.error(f"Error fetching metrics: {e}")
#
# st.divider()

# # =============================================================================
# # STORAGE DETAILS SECTION - COMMENTED OUT
# # =============================================================================
#
# st.subheader("💾 Storage Details")
#
# try:
#     # EDUCATIONAL NOTE - ClickHouse System Tables:
#     # system.parts contains metadata about data storage.
#     # Each "part" is a unit of data in ClickHouse's MergeTree engine.
#     #
#     # Key columns:
#     # - bytes: Uncompressed data size (what the data would be without compression)
#     # - bytes_on_disk: Actual disk usage (after compression)
#     # - rows: Number of rows in this part
#     # - active: Whether this part is current (vs. merged/deleted)
#     #
#     # formatReadableSize() converts bytes to human-readable format (KB, MB, GB).
#     storage_query = """
#     SELECT
#         table,
#         sum(rows) as total_rows,
#         formatReadableSize(sum(bytes)) as size,
#         formatReadableSize(sum(bytes_on_disk)) as compressed_size,
#         sum(bytes) as bytes_uncompressed,
#         sum(bytes_on_disk) as bytes_compressed
#     FROM system.parts
#     WHERE database = 'blockchain_data'
#     AND active = 1
#     GROUP BY table
#     ORDER BY sum(bytes) DESC
#     """
#
#     storage_result = client.query(storage_query)
#
#     if storage_result.result_rows:
#         storage_df = pd.DataFrame(
#             storage_result.result_rows,
#             columns=['Table', 'Rows', 'Uncompressed', 'Compressed', 'Bytes Uncompressed', 'Bytes Compressed']
#         )
#
#         col1, col2 = st.columns([3, 2])
#
#         with col1:
#             # Display table without raw bytes columns (keep human-readable only)
#             display_df = storage_df[['Table', 'Rows', 'Uncompressed', 'Compressed']].copy()
#             st.dataframe(
#                 display_df.style.format({'Rows': '{:,.0f}'}),
#                 use_container_width=True,
#                 height=300,
#                 hide_index=True
#             )
#
#         with col2:
#             # EDUCATIONAL NOTE - Understanding Compression in ClickHouse:
#             #
#             # Compression Ratio = (1 - compressed_size / uncompressed_size) * 100
#             #
#             # ClickHouse achieves high compression (often 80-95%) because:
#             # 1. Columnar storage: Similar values stored together compress well
#             #    (e.g., a column of timestamps has patterns; addresses share prefixes)
#             # 2. LZ4/ZSTD algorithms: Fast, efficient compression codecs
#             # 3. Sorted data: ORDER BY clause means adjacent rows have similar values
#             #
#             # Example: 1GB of blockchain data might compress to 100MB on disk.
#             # This matters for:
#             # - Storage costs (especially in cloud environments)
#             # - Query performance (less data to read from disk)
#             # - Network transfer (for distributed queries)
#             total_uncompressed = storage_df['Bytes Uncompressed'].sum()
#             total_compressed = storage_df['Bytes Compressed'].sum()
#
#             if total_uncompressed > 0:
#                 compression_ratio = (1 - total_compressed / total_uncompressed) * 100
#
#                 # EDUCATIONAL NOTE - Plotly Indicator:
#                 # go.Indicator creates KPI-style visualizations with gauges, numbers, deltas.
#                 # This gauge shows compression ratio with color-coded ranges.
#                 fig = go.Figure(go.Indicator(
#                     mode="gauge+number+delta",
#                     value=compression_ratio,
#                     domain={'x': [0, 1], 'y': [0, 1]},
#                     title={'text': "Compression Ratio"},
#                     delta={'reference': 50},  # Show delta from 50%
#                     gauge={
#                         'axis': {'range': [None, 100]},
#                         'bar': {'color': "darkblue"},
#                         'steps': [
#                             {'range': [0, 30], 'color': "lightgray"},   # Low compression
#                             {'range': [30, 60], 'color': "gray"},       # Medium compression
#                             {'range': [60, 100], 'color': "lightgreen"} # High compression
#                         ],
#                         'threshold': {
#                             'line': {'color': "red", 'width': 4},
#                             'thickness': 0.75,
#                             'value': 90  # Target threshold
#                         }
#                     }
#                 ))
#                 fig.update_layout(height=300)
#                 st.plotly_chart(fig, use_container_width=True)
#
#             # Summary metrics
#             st.metric("Total Uncompressed", storage_df['Uncompressed'].iloc[0] if len(storage_df) > 0 else "0 B")
#             st.metric("Total Compressed", storage_df['Compressed'].iloc[0] if len(storage_df) > 0 else "0 B")
#
# except Exception as e:
#     st.error(f"Error fetching storage details: {e}")

# =============================================================================
# AUTO-REFRESH
# =============================================================================

st.divider()
st.caption("Dashboard auto-refreshes every 5 seconds")
time.sleep(5)
st.rerun()
