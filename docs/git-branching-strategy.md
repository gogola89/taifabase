# Git Branching Strategy - Taifabase

**Date**: 2025-10-04
**Version**: 1.0
**Owner**: Sarah Chen (Project Manager)
**Status**: ACTIVE

---

## Overview

This document defines the Git branching strategy for the Taifabase project. This strategy ensures clean separation of environments, enables safe collaboration, and maintains production-ready code in the `main` branch.

---

## Branch Structure

### 1. **`main` Branch**

**Purpose**: Production-ready code
**Protection**: ✅ Protected (requires PR approval)
**Merge Source**: `staging` only
**Deployment**: Production environment

**Rules**:
- ❌ No direct commits
- ✅ Merge only from `staging` after full validation
- ✅ All commits must be tagged with version numbers
- ✅ Requires 2 approvals for merge
- ✅ CI/CD must pass before merge

**When to Merge**:
- After successful staging validation
- Security review completed
- Performance benchmarks met
- Documentation updated

---

### 2. **`staging` Branch**

**Purpose**: Pre-production testing and integration
**Protection**: ✅ Protected (requires PR approval)
**Merge Source**: `dev` only
**Deployment**: Staging environment

**Rules**:
- ❌ No direct commits
- ✅ Merge from `dev` when sprint milestones complete
- ✅ Requires 1 approval for merge
- ✅ CI/CD must pass before merge
- ✅ QA validation required before promoting to `main`

**When to Merge**:
- Weekly (or end of sprint phase)
- When `dev` is stable and tested
- Before production releases

---

### 3. **`dev` Branch**

**Purpose**: Integration branch for all feature development
**Protection**: ⚠️ Partially protected (requires PR, CI/CD pass)
**Merge Source**: Feature branches
**Deployment**: Development environment

**Rules**:
- ❌ No direct commits (except emergency fixes)
- ✅ Merge feature branches via Pull Requests
- ✅ CI/CD must pass before merge
- ✅ Code review required (1 approval minimum)
- ✅ Daily integration of completed features

**When to Merge**:
- Feature work completed and tested
- All CI/CD checks passing
- Code review approved
- Documentation updated

---

### 4. **Feature Branches**

**Naming Convention**: `day-{N}/{developer-name}/{feature-name}`
**Examples**:
- `day-2/marcus/rls-performance-optimization`
- `day-3/raj/backup-automation`
- `day-5/aisha/load-testing`

**Purpose**: Individual feature development
**Protection**: ❌ No protection (full developer control)
**Merge Source**: `dev`
**Merge Target**: `dev`

**Rules**:
- ✅ Create from `dev` branch
- ✅ Regular commits (every 30-60 minutes)
- ✅ Push to remote daily
- ✅ Pull from `dev` regularly to stay updated
- ✅ Delete after merge to `dev`

**Lifecycle**:
1. **Create**: Branch from latest `dev`
   ```bash
   git checkout dev
   git pull origin dev
   git checkout -b day-3/yourname/feature-name
   ```

2. **Develop**: Regular commits and pushes
   ```bash
   git add .
   git commit -m "feat: descriptive message"
   git push -u origin day-3/yourname/feature-name
   ```

3. **Merge**: Create PR to `dev`
   ```bash
   gh pr create --base dev --title "Day 3: Feature Name" --body "Description"
   ```

4. **Cleanup**: Delete after merge
   ```bash
   git branch -d day-3/yourname/feature-name
   git push origin --delete day-3/yourname/feature-name
   ```

---

## Workflow Diagram

```
main (production)
  ↑
  └── merge from staging (after full validation)

staging (pre-production)
  ↑
  └── merge from dev (weekly/milestone)

dev (integration)
  ↑
  ├── merge from day-2/marcus/rls-optimization
  ├── merge from day-2/raj/pgbouncer-integration
  ├── merge from day-2/aisha/testing-automation
  └── merge from day-2/kenji/security-hardening
```

---

## Pull Request Workflow

### Creating a Pull Request

```bash
# Ensure your branch is up to date
git checkout day-N/yourname/feature-name
git pull origin dev --rebase

# Push your latest changes
git push

# Create PR targeting dev branch
gh pr create \
  --base dev \
  --title "Day N: Feature Name (US-XXX)" \
  --body "$(cat <<'EOF'
## Summary
Brief description of changes

## Changes Made
- List specific changes
- Reference files updated

## Testing Completed
- [ ] Unit tests passing
- [ ] Integration tests passing
- [ ] Manual testing completed

## Documentation Updated
- [ ] Updated existing docs (list files)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### PR Review Checklist

**Reviewer Responsibilities**:
- [ ] Code quality and style
- [ ] Test coverage adequate
- [ ] Documentation updated
- [ ] No security vulnerabilities
- [ ] Performance impact acceptable
- [ ] CI/CD checks passing
- [ ] No merge conflicts

**Approval Criteria**:
- At least 1 approval required for `dev` merge
- CI/CD must be green
- All review comments addressed

---

## Merge Strategies

### Feature → Dev
**Strategy**: Squash and Merge
**Reason**: Clean commit history on `dev`

```bash
gh pr merge --squash --delete-branch
```

### Dev → Staging
**Strategy**: Merge Commit
**Reason**: Preserve feature grouping

```bash
gh pr merge --merge
```

### Staging → Main
**Strategy**: Merge Commit + Tag
**Reason**: Full traceability for production releases

```bash
gh pr merge --merge
git tag -a v1.0.0 -m "Release 1.0.0"
git push origin v1.0.0
```

---

## Environment Mapping

| Branch | Environment | URL | Auto-Deploy |
|--------|-------------|-----|-------------|
| `main` | Production | production.taifabase.io | ✅ Yes |
| `staging` | Staging | staging.taifabase.io | ✅ Yes |
| `dev` | Development | dev.taifabase.io | ✅ Yes |
| Feature | Local | localhost | ❌ No |

---

## CI/CD Pipeline Requirements

### On Feature Branch Push
- ✅ Run unit tests
- ✅ Run linting
- ✅ Check code formatting
- ✅ Security scanning (basic)

### On PR to Dev
- ✅ Run all tests (unit + integration)
- ✅ RLS security tests
- ✅ Performance benchmarks
- ✅ Docker build verification
- ✅ Documentation build check

### On Merge to Dev
- ✅ Deploy to dev environment
- ✅ Run smoke tests
- ✅ Update deployment logs

### On PR to Staging
- ✅ Full test suite
- ✅ Security audit
- ✅ Performance regression tests
- ✅ Load testing
- ✅ QA validation required

### On Merge to Staging
- ✅ Deploy to staging environment
- ✅ Run E2E tests
- ✅ Generate QA report

### On PR to Main
- ✅ All staging checks repeated
- ✅ Security sign-off required
- ✅ Release notes required
- ✅ 2 approvals required

### On Merge to Main
- ✅ Deploy to production
- ✅ Run production smoke tests
- ✅ Create git tag
- ✅ Generate release notes

---

## Hotfix Workflow

For critical production issues:

```bash
# Create hotfix branch from main
git checkout main
git pull origin main
git checkout -b hotfix/critical-issue-name

# Make fix and test thoroughly
git add .
git commit -m "fix: critical issue description"
git push -u origin hotfix/critical-issue-name

# Create PR to main (emergency bypass of dev/staging)
gh pr create --base main --title "HOTFIX: Issue Name"

# After merge to main, backport to dev and staging
git checkout dev
git cherry-pick <hotfix-commit-sha>
git push origin dev

git checkout staging
git cherry-pick <hotfix-commit-sha>
git push origin staging
```

---

## Best Practices

### Commit Messages

Follow conventional commits format:

```
<type>: <subject> (max 50 chars)

<detailed description if needed>

- Bullet points for multiple changes
- Reference issue numbers: Fixes #123
```

**Types**: `feat`, `fix`, `docs`, `perf`, `test`, `security`, `refactor`, `chore`

**Examples**:
```bash
feat: Add PgBouncer connection pooling service
fix: Resolve tenant isolation bug in RLS policies
docs: Update API documentation for auth endpoints
perf: Optimize RLS COUNT queries - reduce 84x to 5x overhead
security: Implement TLS encryption for PostgreSQL
test: Add integration tests for multi-tenant queries
```

### Branch Naming

**Format**: `{type}/{developer}/{description}`

**Types**:
- `day-N` - Sprint day work
- `feature` - New features
- `fix` - Bug fixes
- `hotfix` - Production hotfixes
- `docs` - Documentation only
- `experiment` - Experimental work

**Examples**:
- `day-3/marcus/tenant-management`
- `feature/raj/kubernetes-deployment`
- `fix/aisha/flaky-test-suite`
- `hotfix/kenji/security-vulnerability`

### Keeping Branches Updated

```bash
# Daily: Update your feature branch with latest dev
git checkout day-N/yourname/feature-name
git fetch origin
git rebase origin/dev

# Resolve conflicts if any
git rebase --continue

# Force push (safe because it's your feature branch)
git push --force-with-lease
```

---

## Migration Plan

### Phase 1: Create Branches (Immediate)
```bash
# Create dev branch from main
git checkout main
git pull origin main
git checkout -b dev
git push -u origin dev

# Create staging branch from main
git checkout main
git checkout -b staging
git push -u origin staging
```

### Phase 2: Update PRs (Day 2 completion)
- Change all open PR targets from `main` to `dev`
- Merge all Day 2 PRs to `dev`
- Verify CI/CD passes

### Phase 3: Branch Protection (Day 2 completion)
- Enable branch protection on `main`
  - Require 2 approvals
  - Require CI/CD pass
  - No force push
  - No deletions

- Enable branch protection on `staging`
  - Require 1 approval
  - Require CI/CD pass
  - No force push

- Enable branch protection on `dev`
  - Require 1 approval
  - Require CI/CD pass

### Phase 4: Team Training (Day 3)
- Share this document with team
- Review workflow in standup
- Answer questions
- Monitor first few PRs

---

## Troubleshooting

### Merge Conflicts

```bash
# Update your branch
git checkout your-feature-branch
git fetch origin
git rebase origin/dev

# Resolve conflicts in your editor
# Then:
git add .
git rebase --continue

# Force push (safe on feature branch)
git push --force-with-lease
```

### Accidentally Committed to Wrong Branch

```bash
# If you committed to dev instead of feature branch
git checkout dev
git log -1  # Note the commit SHA
git reset --hard HEAD~1  # Undo the commit

# Create feature branch and apply the commit
git checkout -b day-N/yourname/feature-name
git cherry-pick <commit-sha>
git push -u origin day-N/yourname/feature-name
```

### Need to Update PR Target

```bash
# Via GitHub CLI
gh pr edit <PR-number> --base dev

# Or via GitHub web interface
```

---

## Summary

**Key Points**:
1. **`main`** = Production-ready only
2. **`staging`** = Pre-production validation
3. **`dev`** = Daily integration of features
4. **Feature branches** = Individual work

**Daily Workflow**:
1. Create feature branch from `dev`
2. Develop and commit regularly
3. Create PR to `dev`
4. Get code review
5. Merge to `dev`
6. Delete feature branch

**Release Workflow**:
1. Sprint work merges to `dev` daily
2. `dev` merges to `staging` weekly
3. `staging` merges to `main` when validated
4. Tag releases on `main`

---

## Contacts

- **Git Workflow Questions**: Sarah Chen (@sarah.chen)
- **CI/CD Issues**: Raj Patel (@raj.patel)
- **Code Review Process**: Aisha Kamau (@aisha.kamau)
- **Security Reviews**: Dr. Kenji Tanaka (@kenji.tanaka)

---

**Status**: ✅ **ACTIVE**
**Last Updated**: 2025-10-04
**Next Review**: End of Sprint 1

*This branching strategy ensures clean, safe, and collaborative development for Taifabase.*
