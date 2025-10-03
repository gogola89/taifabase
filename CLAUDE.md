# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Taifabase** is an open-source Backend-as-a-Service (BaaS) platform designed as a production-ready alternative to Supabase. It provides developers with a self-hosted, secure, and scalable backend infrastructure that can be deployed anywhere.

## Architecture

This is a documentation and planning repository for the Taifabase project. The repository contains:

- **Documentation (`docs/`)**: Project vision, planning documents, and technical specifications
- **Personas (`.claude/personas/`)**: AI agent personas for specialized development roles
- **Project Structure**: Planning artifacts and team coordination documents

### Current Development Phase

**Phase 1: Database Foundation** (4 weeks, current priority)
- Production-ready PostgreSQL setup with Row-Level Security (RLS)  
- PgBouncer connection pooling implementation
- Multi-tenant isolation using RLS policies
- Docker Compose for local development
- Kubernetes manifests for production deployment
- Automated backup system with WAL archiving
- Monitoring and alerting setup (Prometheus/Grafana)

## Technology Stack

**Core Technologies:**
- **Database**: PostgreSQL 15+ with Row-Level Security (RLS)
- **Connection Pooling**: PgBouncer
- **Authentication**: GoTrue (Supabase's auth service)
- **Storage**: MinIO (S3-compatible object storage)
- **Realtime**: WebSocket-based subscriptions
- **API**: RESTful and GraphQL interfaces
- **Admin Dashboard**: React + TypeScript UI
- **Infrastructure**: Docker + Kubernetes
- **Monitoring**: Prometheus + Grafana

## Team Structure

The project uses specialized AI personas for development:

1. **Project Manager** (`.claude/personas/project-manager.md`)
   - Sprint planning and backlog management
   - Risk management and stakeholder communication
   - Documentation and process coordination

2. **Backend Engineer** (`.claude/personas/backend-engineer.md`) 
   - PostgreSQL expertise (RLS, performance tuning)
   - Go programming for microservices
   - API development and database optimization

3. **DevOps Engineer** (`.claude/personas/devops-engineer.md`)
   - Kubernetes and Docker orchestration
   - Infrastructure as Code (Terraform, Helm)
   - Monitoring and observability setup

4. **QA Engineer** (`.claude/personas/qa-engineer.md`)
   - Test strategy and automation
   - Performance and security testing
   - Quality assurance processes

5. **Security Engineer** (`.claude/personas/security-engineer.md`)
   - Security architecture and threat modeling
   - Compliance (SOC2, GDPR) and vulnerability management
   - Infrastructure hardening

6. **Frontend Engineer** (`.claude/personas/frontend-engineer.md`)
   - React/Next.js dashboard development (Phase 5)
   - UI/UX for developer tools
   - Real-time features integration

## Usage with Claude Code

### Using Personas

Invoke specialized personas for domain-specific tasks:

```bash
# Project management and planning
claude code --persona .claude/personas/project-manager.md

# Backend development
claude code --persona .claude/personas/backend-engineer.md

# Infrastructure and deployment
claude code --persona .claude/personas/devops-engineer.md

# Testing and quality assurance
claude code --persona .claude/personas/qa-engineer.md

# Security and compliance
claude code --persona .claude-engineer.md

# Frontend development (Phase 5)
claude code --persona .claude/personas/frontend-engineer.md
```

### Project Kickoff

For Phase 1 initialization, use the Project Manager persona with the kickoff documentation:

```bash
claude code --persona .claude/personas/project-manager.md --file docs/start/kick-off.md
```

## Documentation Structure

- **Vision Document**: `docs/start/vision.md` - Comprehensive project vision and roadmap
- **Team Personas**: `docs/start/agents.md` - Detailed persona descriptions and responsibilities  
- **Kickoff Guide**: `docs/start/kick-off.md` - Step-by-step project initialization process

## Development Approach

- **Agile Methodology**: 2-week sprints with defined ceremonies
- **Quality Standards**: >80% test coverage, security-first design, comprehensive documentation
- **Security by Design**: TLS everywhere, least privilege access, audit logging
- **Documentation as Code**: All documentation in Markdown, version controlled
- **Infrastructure as Code**: Kubernetes manifests, Helm charts, Terraform modules

## Phase Roadmap

1. **Phase 1**: Database Foundation (4 weeks) - *Current*
2. **Phase 2**: Authentication Service (6 weeks)
3. **Phase 3**: Storage Service (4 weeks) 
4. **Phase 4**: API Layer (6 weeks)
5. **Phase 5**: Admin Dashboard (8 weeks)
6. **Phase 6**: Production Hardening (4 weeks)

## Repository Standards

- Use Markdown for all documentation
- Follow GitOps principles for configuration management
- Maintain detailed commit messages with context
- Cross-reference related documents and decisions
- Include metadata (date, version, owner) in documents
- Prioritize security and compliance requirements in all phases

## Getting Started

1. Review the project vision: `docs/start/vision.md`
2. Understand team structure: `docs/start/agents.md`  
3. Follow kickoff process: `docs/start/kick-off.md`
4. Use appropriate persona for your task domain
5. Maintain documentation alongside all development work