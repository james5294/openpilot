# CI/CD Blueprint for Fork Swap WebUI

## Overview

This blueprint defines the continuous integration and deployment pipeline for the Fork Swap WebUI component.

---

## Pipeline Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                          Git Push / PR                                │
└─────────────────────────────────┬────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────┐
│                         STAGE 1: LINT                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                   │
│  │ ruff check  │  │ruff format  │  │   mypy      │                   │
│  │   (lint)    │  │  (style)    │  │  (types)    │                   │
│  └─────────────┘  └─────────────┘  └─────────────┘                   │
└─────────────────────────────────┬────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────┐
│                      STAGE 2: UNIT TESTS                              │
│  ┌─────────────────────────────────────────────────────────────┐     │
│  │ pytest unit/ - Fast, isolated tests (~50 tests, <30s)       │     │
│  └─────────────────────────────────────────────────────────────┘     │
└─────────────────────────────────┬────────────────────────────────────┘
                                  │
                         ┌────────┴────────┐
                         │                 │
                         ▼                 ▼
┌────────────────────────────┐ ┌────────────────────────────┐
│   STAGE 3A: INTEGRATION    │ │   STAGE 3B: SECURITY       │
│ ┌────────────────────────┐ │ │ ┌────────────────────────┐ │
│ │ pytest integration/    │ │ │ │ pytest security/       │ │
│ │ HTTP handlers (~25)    │ │ │ │ Injection tests (~40)  │ │
│ └────────────────────────┘ │ │ └────────────────────────┘ │
│                            │ │ ┌────────────────────────┐ │
│                            │ │ │ bandit scanner         │ │
│                            │ │ └────────────────────────┘ │
└────────────────┬───────────┘ └───────────────┬────────────┘
                 │                             │
                 └──────────────┬──────────────┘
                                │
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│                       STAGE 4: COVERAGE                               │
│  ┌─────────────────────────────────────────────────────────────┐     │
│  │ pytest --cov - Combined coverage report                      │     │
│  │ Threshold: 30% (Stage 1) → 70% (Stage 2) → 85% (Stage 3)    │     │
│  └─────────────────────────────────────────────────────────────┘     │
└─────────────────────────────────┬────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    STAGE 5: QUALITY GATE                              │
│  ┌─────────────────────────────────────────────────────────────┐     │
│  │ All critical tests must pass                                 │     │
│  │ Coverage threshold met                                       │     │
│  │ No high-severity security findings                           │     │
│  └─────────────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────────────┘
```

---

## GitHub Actions Workflow

### Workflow File

`.github/workflows/webui-tests.yml`

### Triggers

| Event | Branches | Paths |
|-------|----------|-------|
| `push` | main, master, forkswap | webui/** |
| `pull_request` | main, master, forkswap | webui/** |
| `workflow_dispatch` | any | manual |

### Jobs

| Job | Depends On | Purpose | Timeout |
|-----|------------|---------|---------|
| `lint` | - | Code quality checks | 5min |
| `unit-tests` | lint | Fast unit tests | 10min |
| `integration-tests` | unit-tests | HTTP handler tests | 15min |
| `security-tests` | unit-tests | Security validation | 10min |
| `coverage` | all tests | Combined coverage | 15min |
| `all-tests-passed` | all | Quality gate | 1min |

---

## Local Development Commands

### Run All Tests
```bash
cd webui/tests
pip install pytest pytest-asyncio aiohttp
python -m pytest . -v
```

### Run by Category
```bash
# Unit tests only (fast)
python -m pytest unit/ -v

# Integration tests
python -m pytest integration/ -v

# Security tests
python -m pytest security/ -v
```

### With Coverage
```bash
pip install pytest-cov
python -m pytest . --cov=../server --cov-report=html
open coverage_html/index.html
```

### Lint Locally
```bash
pip install ruff mypy
ruff check webui/
ruff format --check webui/
mypy webui/server.py --ignore-missing-imports
```

---

## Coverage Targets

### Staged Rollout

| Stage | Timeline | Target | Enforcement |
|-------|----------|--------|-------------|
| Stage 1 | Week 1-2 | 30% | Warning only |
| Stage 2 | Week 3-4 | 50% | PR checks fail |
| Stage 3 | Week 5-6 | 70% | Merge blocked |
| Stage 4 | Week 7-8 | 85% | Full enforcement |

### Coverage by Module

| Module | Current | Target | Priority |
|--------|---------|--------|----------|
| Validation functions | ~90% | 95% | LOW |
| Core functions | ~40% | 80% | HIGH |
| HTTP handlers | ~20% | 70% | HIGH |
| AGNOS management | ~30% | 70% | MEDIUM |
| Security tests | ~60% | 90% | HIGH |

---

## Quality Gates

### PR Merge Requirements

1. **All unit tests pass** (blocking)
2. **All integration tests pass** (blocking)
3. **All security tests pass** (blocking)
4. **Coverage threshold met** (staged)
5. **No high-severity bandit findings** (blocking after Stage 2)

### Branch Protection Rules

```yaml
# Recommended branch protection for main/forkswap
required_status_checks:
  strict: true
  contexts:
    - "Unit Tests"
    - "Integration Tests"
    - "Security Tests"
    - "All Tests Passed"
```

---

## Test Artifacts

### Generated Artifacts

| Artifact | Path | Retention |
|----------|------|-----------|
| Unit test results | `unit-results.xml` | 30 days |
| Integration test results | `integration-results.xml` | 30 days |
| Security test results | `security-results.xml` | 30 days |
| Bandit report | `bandit-report.json` | 30 days |
| Coverage HTML | `coverage_html/` | 30 days |
| Coverage XML | `coverage.xml` | 30 days |

### Viewing Artifacts

1. Go to Actions tab in GitHub
2. Click on workflow run
3. Scroll to Artifacts section
4. Download and extract

---

## Security Scanning

### Bandit Integration

Bandit scans `server.py` for:
- Hardcoded passwords
- SQL injection risks
- Command injection patterns
- Insecure function usage

### Expected Findings

| Finding | Severity | Status | Notes |
|---------|----------|--------|-------|
| `subprocess` usage | MEDIUM | Accepted | Required for fork_swap.sh |
| `hmac.compare_digest` | LOW | Accepted | Intentional timing-safe |

---

## Environment Variables

### CI Environment

| Variable | Value | Purpose |
|----------|-------|---------|
| `FORKSWAP_TEST_MODE` | `1` | Enable test isolation |
| `PYTHONPATH` | `$GITHUB_WORKSPACE/webui` | Module resolution |

### Local Testing

```bash
export FORKSWAP_TEST_MODE=1
export PYTHONPATH=/path/to/opforks/webui
```

---

## Troubleshooting

### Common CI Failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| Import error | PYTHONPATH not set | Add to env in workflow |
| Async test timeout | Missing pytest-asyncio | Add to dependencies |
| Coverage too low | New code without tests | Add tests before merge |
| Bandit failure | Security issue | Fix or document exception |

### Local vs CI Differences

| Issue | Local | CI | Resolution |
|-------|-------|-----|------------|
| Path separator | macOS `/` | Linux `/` | Use `Path()` |
| Python version | 3.13 | 3.11 | Specify in workflow |
| aiohttp missing | Optional | Required | Install in CI |

---

## Future Enhancements

### Phase 2 Additions

- [ ] Mutation testing with `mutmut`
- [ ] Property-based testing with `hypothesis`
- [ ] End-to-end tests with real subprocess
- [ ] Device emulation tests

### Phase 3 Additions

- [ ] Performance regression tests
- [ ] Load testing with `locust`
- [ ] Dependency vulnerability scanning
- [ ] SBOM generation

---

## Commands Reference

```bash
# Install all dev dependencies
pip install pytest pytest-asyncio pytest-cov aiohttp ruff mypy bandit

# Run full test suite with coverage
python -m pytest . --cov=../server --cov-report=term-missing

# Run only failing tests
python -m pytest --lf

# Run with verbose output
python -m pytest -vvs

# Run specific test
python -m pytest unit/test_validation.py::TestValidateForkName::test_valid_simple_names

# Generate HTML coverage report
python -m pytest . --cov=../server --cov-report=html
```

---

*Blueprint version: 1.0.0*
*Last updated: 2026-01-15*
