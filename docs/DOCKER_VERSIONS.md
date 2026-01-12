# Docker Version Management

## Current Versions

- **ClickHouse**: 25.10-alpine
- **Python**: 3.11-slim
- **Node**: 22-alpine

## Version Pinning Policy

All production Docker images MUST be pinned to specific versions (not `latest`).

### Why We Pin Versions

1. **Reproducibility**: Same build works on any machine at any time
2. **Stability**: Prevents unexpected breaking changes from automatic updates
3. **Security**: Controlled upgrade path with proper testing before deployment

### When to Update Versions

Update Docker image versions when:

1. **Security vulnerabilities** are discovered in current versions
2. **Required features** are only available in newer versions
3. **Quarterly review cycle** identifies maintenance benefits
4. **Compatibility issues** require a specific version upgrade

### How to Update Versions

Follow these steps when updating any Docker image version:

1. **Update `docker-compose.yml`** with the new version tag
2. **Test locally**:
   ```bash
   docker compose down -v
   docker compose up --build
   ```
3. **Verify all services start successfully** and health checks pass
4. **Run integration tests** to ensure no regressions
5. **Document the change** in this file's Version History table
6. **Commit with descriptive message**:
   ```
   chore: Update [service] from X.Y.Z to A.B.C

   Reason: [security fix|feature requirement|compatibility]
   Breaking changes: [yes/no]
   ```

## Version Verification

The `scripts/start.sh` script includes automated version verification to catch mismatches early. If you see a version warning, check this file to confirm the expected version.

## Version History

| Date | Service | From | To | Reason | Commit |
|------|---------|------|----|----|--------|
| 2026-01-12 | ClickHouse | 24.1.8-alpine | 25.10-alpine | Fix API compatibility issues and JSON response format differences | [current] |
| 2025-XX-XX | ClickHouse | latest | 24.1.8-alpine | Pin for reproducibility in production | 83c54da |

## ClickHouse Version Notes

### Version 25.10 (Current)

- **Stability**: Stable release with better JSON response handling
- **Compatibility**: Full compatibility with `@clickhouse/client` 1.16.0+
- **JSON Format**: Consistent `JSONEachRow` format returns arrays as expected
- **Known Issues**: None

### Version 24.1.8 (Previous)

- **Issues**:
  - Inconsistent JSON response formats (sometimes returned objects instead of arrays)
  - Incompatibility with newer client libraries
  - API 500 errors due to type mismatches
- **Deprecated**: Should not be used going forward

## Troubleshooting

### Build Fails After Version Update

1. Clear all Docker caches:
   ```bash
   docker compose down -v
   docker system prune -a
   ```
2. Rebuild from scratch:
   ```bash
   docker compose up --build
   ```

### Version Mismatch Warnings

If `start.sh` reports a version mismatch:

1. Check `docker-compose.yml` for the actual version
2. Verify this document reflects the correct expected version
3. Update either the config or documentation to match

### Services Won't Start After Upgrade

1. Check Docker logs: `docker compose logs [service]`
2. Verify volume compatibility (may need to delete old volumes)
3. Check for breaking changes in release notes
4. Rollback if needed and investigate before retrying

## References

- [ClickHouse Release Notes](https://clickhouse.com/docs/en/whats-new/changelog)
- [Node.js Release Schedule](https://nodejs.org/en/about/previous-releases)
- [Python Release Status](https://devguide.python.org/versions/)
