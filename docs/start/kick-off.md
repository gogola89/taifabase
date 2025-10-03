# Project Manager Kickoff Prompt for Taifabase Phase 1

## Initial Setup Command

```bash
claude code --persona .claude/personas/project-manager.md
```

---

## Complete Kickoff Prompt

```
You are the Project Manager for Taifabase, an open-source Backend-as-a-Service platform. 
We're starting Phase 1: Database Foundation (4 weeks, 2 sprints of 2 weeks each).

PROJECT CONTEXT:
- Building a production-ready PostgreSQL setup with Row-Level Security (RLS)
- Implementing PgBouncer connection pooling for multi-tenant architecture
- Setting up Docker Compose for local dev and Kubernetes for production
- Establishing monitoring, backups, and complete documentation
- Timeline: 4 weeks (Sprint 1: Weeks 1-2, Sprint 2: Weeks 3-4)

TEAM COMPOSITION:
- You (Project Manager)
- Backend Engineer (PostgreSQL/Go expert)
- DevOps Engineer (Kubernetes/Infrastructure expert)
- QA Engineer (Testing and quality assurance)
- Security Engineer (Security and compliance)
- Frontend Engineer (Will join in later phase)

YOUR MISSION:
Create a complete project setup for Phase 1 with the following deliverables:

1. PRODUCT BACKLOG (backlogs/product-backlog.md)
   - Break Phase 1 into 4-6 Epics
   - Create 20-30 detailed User Stories
   - Use MoSCoW prioritization (Must/Should/Could/Won't)
   - Format: Title, Description, Acceptance Criteria (Given/When/Then), Technical Notes, Dependencies, Story Points, Priority

2. EPIC BREAKDOWN (backlogs/phase1-epics.md)
   - Epic 1: Multi-tenant PostgreSQL Setup
   - Epic 2: Connection Pooling with PgBouncer
   - Epic 3: Local Development Environment
   - Epic 4: Production Kubernetes Deployment
   - Epic 5: Monitoring and Observability
   - Epic 6: Backup and Disaster Recovery
   - Each epic: Objective, Success Criteria, User Stories, Technical Scope

3. SPRINT 1 PLAN (sprints/sprint-1-plan.md)
   - Sprint Goal: "Establish foundational database infrastructure with multi-tenancy"
   - Duration: 2 weeks
   - Team velocity estimate: 40-50 story points
   - Selected user stories with assignments
   - Daily standup schedule (time and format)
   - Sprint ceremonies calendar
   - Sprint deliverables and demo plan
   - Definition of Done

4. SPRINT 2 PLAN (sprints/sprint-2-plan.md)
   - Sprint Goal: "Production deployment readiness with monitoring and backups"
   - Duration: 2 weeks
   - Selected user stories building on Sprint 1
   - Production deployment focus
   - Sprint ceremonies calendar
   - Sprint deliverables and demo plan

5. RISK REGISTER (docs/risk-register.md)
   - Identify 10-15 risks across technical, resource, timeline categories
   - For each risk: Description, Likelihood (High/Medium/Low), Impact (High/Medium/Low), Mitigation Strategy, Owner, Status
   - Include dependency risks and external blockers

6. DEFINITION OF DONE (docs/definition-of-done.md)
   - Story-level DoD (code complete, tested, reviewed, documented)
   - Sprint-level DoD (all stories done, demo ready, deployed to staging)
   - Phase-level DoD (production ready, documented, security reviewed)
   - Quality gates and acceptance criteria

7. TEAM WORKING AGREEMENT (docs/team-working-agreement.md)
   - Communication protocols (when to use async vs sync)
   - Code review process and SLAs
   - Meeting schedules and attendance expectations
   - Decision-making framework
   - Conflict resolution process
   - On-call and support rotation (future)

8. PROJECT VISION DOCUMENT (docs/product-vision.md)
   - Expand on the vision provided
   - Phase 1 objectives and key results (OKRs)
   - Success metrics and KPIs
   - Technical architecture overview
   - Quality standards
   - Open-source strategy

9. PHASE 1 ROADMAP (docs/phase1-roadmap.md)
   - Week-by-week breakdown
   - Key milestones and checkpoints
   - Demo schedule
   - Go/No-Go criteria for Phase 2
   - Dependencies on external services/tools

10. COMMUNICATION PLAN (docs/communication-plan.md)
    - Stakeholder identification and needs
    - Status report format and cadence (weekly)
    - Demo and review schedule
    - Escalation paths and decision makers
    - Documentation standards

QUALITY STANDARDS TO ENFORCE:
- All user stories must have clear acceptance criteria (Given/When/Then)
- Story points using Fibonacci sequence (1, 2, 3, 5, 8, 13, 21)
- Technical debt tracked as separate stories
- Security and performance considered in every story
- Test coverage requirements specified (>80%)
- Documentation created alongside development

OUTPUT REQUIREMENTS:
- Create ALL documents in Markdown format
- Save to appropriate folders (docs/, backlogs/, sprints/)
- Use consistent formatting and structure
- Include tables, checklists, and diagrams where helpful
- Cross-reference related documents
- Add metadata (date, version, owner) to each document

ADDITIONAL TASKS:
- Create a project kickoff meeting agenda
- Draft initial status report template
- Identify key decision points requiring team input
- Highlight any assumptions that need validation
- Flag any immediate blockers or concerns

Please proceed to create all deliverables. Start with the Product Vision and Roadmap, 
then create the Backlog and Epics, followed by Sprint Plans, and finally the 
supporting documents (Risk Register, DoD, Working Agreement, Communication Plan).

For each deliverable, create complete, production-ready content - no placeholders or TODOs.
Think like an experienced PM who has done this many times before.
```

---

## Alternative: Phased Kickoff Approach

If you want to work iteratively with the PM, use this phased approach:

### Phase A: Vision and Planning Foundation
```bash
claude code --persona .claude/personas/project-manager.md "Create the foundational planning documents for Taifabase Phase 1:

1. Product Vision Document (docs/product-vision.md)
2. Phase 1 Roadmap with week-by-week breakdown (docs/phase1-roadmap.md)
3. Risk Register with initial risks identified (docs/risk-register.md)

Use the project details from vision.md file. Make these comprehensive and production-ready."
```

### Phase B: Backlog Creation
```bash
claude code --persona .claude/personas/project-manager.md "Based on the vision and roadmap, create:

1. Epic Breakdown (backlogs/phase1-epics.md) - Break Phase 1 into 6 major epics
2. Product Backlog (backlogs/product-backlog.md) - Create 25-30 detailed user stories with:
   - Acceptance criteria in Given/When/Then format
   - Story points estimates
   - MoSCoW prioritization
   - Technical notes and dependencies

Focus on stories for: PostgreSQL setup, RLS policies, PgBouncer, Docker Compose, 
Kubernetes deployment, monitoring, backups, security, and documentation."
```

### Phase C: Sprint Planning
```bash
claude code --persona .claude/personas/project-manager.md "Create detailed sprint plans:

1. Sprint 1 Plan (sprints/sprint-1-plan.md) - Focus on foundational database setup
2. Sprint 2 Plan (sprints/sprint-2-plan.md) - Focus on production readiness

Each sprint plan should include:
- Sprint goal and objectives
- Selected user stories (40-50 points per sprint)
- Team capacity planning
- Daily standup schedule
- Sprint ceremonies calendar
- Deliverables and demo plan
- Risks and dependencies"
```

### Phase D: Team Processes
```bash
claude code --persona .claude/personas/project-manager.md "Create team process documents:

1. Definition of Done (docs/definition-of-done.md) - Story, Sprint, and Phase levels
2. Team Working Agreement (docs/team-working-agreement.md) - Collaboration guidelines
3. Communication Plan (docs/communication-plan.md) - Stakeholder management
4. Status Report Template (docs/status-report-template.md) - Weekly updates

Make these practical and actionable for an AI development team."
```

---

## Follow-up Prompts After Initial Setup

### Review and Refinement
```bash
claude code --persona .claude/personas/project-manager.md "Review all Phase 1 planning documents and:

1. Identify any gaps or missing user stories
2. Check for dependency conflicts between stories
3. Validate story point estimates are reasonable
4. Ensure sprint goals are achievable
5. Highlight any risks that need immediate attention
6. Suggest any adjustments to improve the plan"
```

### Get Technical Input
```bash
claude code --persona .claude/personas/backend-engineer.md "Review the Product Backlog 
(backlogs/product-backlog.md) and provide technical input:

1. Validate story point estimates from backend perspective
2. Identify missing technical requirements
3. Flag any technical risks or blockers
4. Suggest story dependencies and sequencing
5. Provide implementation notes for complex stories"
```

### Get DevOps Input
```bash
claude code --persona .claude/personas/devops-engineer.md "Review the Product Backlog 
and Sprint Plans from infrastructure perspective:

1. Validate Kubernetes and Docker stories
2. Identify infrastructure dependencies
3. Suggest monitoring and observability requirements
4. Review backup and disaster recovery stories
5. Provide deployment architecture recommendations"
```

### Get Security Input
```bash
claude code --persona .claude/personas/security-engineer.md "Review the Product Backlog 
from security perspective:

1. Identify security gaps in user stories
2. Suggest additional security stories
3. Review RLS policy implementation approach
4. Validate secrets management strategy
5. Recommend security testing requirements"
```

### Get QA Input
```bash
claude code --persona .claude/personas/qa-engineer.md "Review the Product Backlog 
and create testing strategy:

1. Identify testability gaps in user stories
2. Create test plan for Phase 1
3. Define quality gates for each sprint
4. Suggest test automation requirements
5. Provide test coverage targets"
```

---

## Quick Start: Single Command Approach

If you want everything at once:

```bash
claude code --persona .claude/personas/project-manager.md --file vision.md "You are 
starting as PM for Taifabase Phase 1. Read the vision.md file thoroughly and create 
ALL project planning deliverables:

DELIVERABLES (in order):
1. docs/product-vision.md - Comprehensive vision document
2. docs/phase1-roadmap.md - Week-by-week roadmap
3. backlogs/phase1-epics.md - 6 epic breakdown
4. backlogs/product-backlog.md - 25-30 user stories
5. sprints/sprint-1-plan.md - Sprint 1 detailed plan
6. sprints/sprint-2-plan.md - Sprint 2 detailed plan
7. docs/risk-register.md - Risk identification and mitigation
8. docs/definition-of-done.md - Quality standards
9. docs/team-working-agreement.md - Team processes
10. docs/communication-plan.md - Stakeholder management

Create complete, production-ready documents with no placeholders. Think like an 
experienced technical PM. Include all details: acceptance criteria, story points, 
dependencies, technical notes, schedules, and quality gates.

Start working through these systematically, creating each file in the appropriate 
directory."
```

---

## Verification Checklist

After the PM completes the kickoff, verify:

- [ ] All 10 documents created in correct directories
- [ ] Product backlog has 25-30 detailed user stories
- [ ] Each story has acceptance criteria in Given/When/Then format
- [ ] Story points assigned (Fibonacci: 1,2,3,5,8,13,21)
- [ ] MoSCoW prioritization applied
- [ ] Sprint 1 has 40-50 story points selected
- [ ] Sprint 2 has 40-50 story points selected
- [ ] Sprint goals are clear and achievable
- [ ] Risk register has 10-15 risks with mitigation
- [ ] Definition of Done covers Story/Sprint/Phase levels
- [ ] Communication plan includes stakeholder matrix
- [ ] All documents cross-reference each other
- [ ] Technical debt tracking process defined
- [ ] Quality gates clearly specified

---

## Next Steps After PM Kickoff

1. **Technical Validation** (Day 1-2)
   - Backend Engineer reviews technical stories
   - DevOps Engineer reviews infrastructure stories
   - Security Engineer reviews security requirements
   - QA Engineer creates test strategy

2. **Sprint 1 Kickoff** (Day 3)
   - Sprint planning meeting
   - Story refinement with technical team
   - Commitment to sprint goal
   - Setup development environment

3. **Daily Execution** (Days 4-14)
   - Daily standups
   - Story development
   - Code reviews
   - Testing
   - Documentation

4. **Sprint 1 Review & Retro** (Day 14)
   - Demo completed stories
   - Retrospective and improvements
   - Sprint 2 refinement

---

## Tips for Using the PM Persona

1. **Be Specific**: The more context you provide, the better the output
2. **Iterate**: Review outputs and ask for refinements
3. **Cross-Check**: Have other personas review PM's work
4. **Use Files**: Reference vision.md and other docs in prompts
5. **Save Progress**: Commit documents to Git after each major deliverable
6. **Ask Questions**: The PM can help clarify requirements and priorities

---

## Example Conversation Flow

```bash
# 1. PM creates initial planning documents
claude code --persona project-manager.md --file vision.md "[kickoff prompt]"

# 2. Review and ask for adjustments
claude code --persona project-manager.md "The backlog looks good but I think we need 
more stories around security hardening. Can you add 5 more security-focused stories?"

# 3. Get technical validation
claude code --persona backend-engineer.md --file backlogs/product-backlog.md "Review 
these stories and provide technical feasibility assessment"

# 4. Refine based on feedback
claude code --persona project-manager.md "Based on the backend engineer's feedback, 
adjust story US-103 to split it into two smaller stories"

# 5. Start Sprint 1
claude code --persona project-manager.md "Create Sprint 1 kickoff meeting agenda and 
first week daily standup notes template"
```

This approach gives you full control over the project setup while leveraging the PM 
persona's expertise!