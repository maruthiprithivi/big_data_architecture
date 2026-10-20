# Verification record — 20 October 2026

## Actual coverage

| Environment | Startup + actual model + database + HTML build | Evidence |
|---|---|---|
| macOS host, Apple Silicon, native Linux ARM64 containers | PASS, four prompts | `tests-arm64.json` |
| Same Mac, Linux AMD64 containers under Docker Desktop emulation | PASS, four prompts | `tests-amd64.json` |
| Bash and PowerShell 7.4.6 launchers on macOS, actual Docker stack | PASS preflight/setup/postflight; exported JSON + HTML | `tests-launchers.json` |
| Native Windows Docker Desktop / WSL 2 host | **Not available; not tested** | Run the portable command below on a classroom Windows machine |
| Native Intel Mac host | **Not available; not tested** | AMD64 container behavior was tested under emulation, not native Intel hardware |

These tests do not establish that Windows host installation, WSL configuration, filesystem sharing or corporate policy will work. Linux images advertise ARM64/AMD64 in their pinned multi-platform manifests. The Bash/PowerShell launchers require only Docker on the host. The PowerShell launcher uses Windows PowerShell 5.1-compatible syntax; its logic is also exercised using PowerShell 7.4.6 on macOS. This is not a native Windows host test. Do not describe x86 emulation as a native Windows test.

Docker Desktop engine: Linux/aarch64, 10 CPUs, approximately 7.75 GiB VM allocation. Each service ran under the packaged memory caps; **the Desktop VM itself was not reconfigured to 4 GiB**. The sum of all caps, including downloader, is 3,716 MiB (3.63 GiB). Model: 2,300 MiB, database: 1,000 MiB, app: 256 MiB, downloader: 160 MiB. This bounds container memory, excluding engine/VM/OS overhead. Neither native nor emulated run was OOM-killed. `tests-resources.json` records limits, observed cgroup peaks when available, and OOM flags. Do not present independently sampled peaks as a simultaneous workload measurement.

Cold native startup downloaded the model from its official pinned revision and verified SHA-256. AMD64 startup reused those same verified bytes from the model volume, then initialized a fresh database. Native final four investigations took approximately 2–4 seconds each; AMD64 emulation took approximately 8–18 seconds each. These are observations on this test Mac, not promises for student hardware or a database benchmark.

## What the E2E verifies

- Actual local-model JSON plans select starts, engaged count, engagement rate and a 40-minute/device query correctly.
- Actual ClickHouse queries yield one million total sessions, known winners/values, and zero engaged sessions at forty minutes.
- Numeric observations come from returned rows, and ties are explicit. No numeric conclusion is delegated to free-form model prose.
- A downloadable escaped HTML dashboard includes the actual rows and executed SQL.
- Invalid plans/thresholds/prompts are rejected; model text cannot be interpolated as SQL or executed as code.
- The database reader independently rejects DROP TABLE with ACCESS_DENIED.
- Cross-origin write requests are rejected.
- Browser checks cover starter prompt selection, disabled/loading state, evidence rendering, SQL/trace disclosure, HTML download contents, and responsive overflow. QR codes are decoded back to the LinkedIn and actual student-repository URLs.

## Reproduce on the classroom hosts

Download/extract the lab-only release ZIP and open `campusstream-agent-lab`, or use `labs/campusstream-agent-lab` in a course checkout:

| Action | macOS · Terminal | Windows · PowerShell |
|---|---|---|
| Check prerequisites | `bash lab.sh preflight` | `powershell -NoProfile -ExecutionPolicy Bypass -File .\lab.ps1 preflight` |
| Set up and wait until ready | `bash lab.sh setup` | `powershell -NoProfile -ExecutionPolicy Bypass -File .\lab.ps1 setup` |
| Verify the whole lab | `bash lab.sh postflight` | `powershell -NoProfile -ExecutionPolicy Bypass -File .\lab.ps1 postflight` |

Setup includes preflight. Postflight saves `results/postflight.json` and `results/dashboard.html` after all real checks pass. Open http://localhost:8090, ask a starter prompt, inspect the trace and download your own dashboard too. Record the classroom host OS/CPU, Docker version/allocation and latency with its receipt. Stop with `docker compose down`; the model cache is retained.

Launcher checks: `python3 tests/test_launchers.py` tests Bash, and also PowerShell if `PWSH` points to a runtime. These developer-only checks simulate engine-down, Windows-container mode, too little Docker memory (accepts 3.75 GiB reported after a 4 GiB allocation reserves some for Linux), failed startup and failed E2E. They assert nonzero exits, no continuation after failure, read-only preflight, correct readiness invocation, receipt copying and execution from a path containing spaces. They do not replace actual model/database tests. No Python is required on student hosts.

For development-only x86 emulation after a native run has populated `campusstream_model-cache`, stop the native stack first (same port), then:

```text
docker compose -p campusstream-amd64 -f compose.yaml -f tests/amd64.compose.yaml up --build -d
docker compose -p campusstream-amd64 -f compose.yaml -f tests/amd64.compose.yaml exec -T app python verify.py
docker compose -p campusstream-amd64 -f compose.yaml -f tests/amd64.compose.yaml down
```

The override shares only the pinned model cache, not database containers. It is not the student startup path.
