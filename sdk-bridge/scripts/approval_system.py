#!/usr/bin/env python3
"""
Approval System - SDK Bridge v2.0 Phase 2

Risk assessment and human-in-the-loop approval workflow for high-risk operations.

Features:
- Automated risk classification
- Approval queue management
- Async approval workflow (non-blocking)
- Alternative suggestion system

Author: SDK Bridge Team
Version: 2.0.0-alpha (Phase 2)
"""

import json
import logging
import re
import uuid
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone, timedelta
from enum import Enum
from pathlib import Path
from typing import Dict, List, Optional, Any


logger = logging.getLogger("approval_system")


class RiskLevel(Enum):
    """Risk classification levels."""
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


class ApprovalStatus(Enum):
    """Approval request status."""
    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"
    TIMEOUT = "timeout"


@dataclass
class RiskRule:
    """Rule for risk classification."""
    name: str
    keywords: List[str]
    risk_level: RiskLevel
    auto_approve: bool
    requires_rollback_plan: bool = False
    requires_backup: bool = False


# Risk classification rules
RISK_RULES = [
    RiskRule(
        name="database_migration",
        keywords=["drop table", "drop column", "alter table", "migration", "schema change"],
        risk_level=RiskLevel.HIGH,
        auto_approve=False,
        requires_rollback_plan=True
    ),
    RiskRule(
        name="data_deletion",
        keywords=["delete from", "truncate", "drop database", "remove data"],
        risk_level=RiskLevel.HIGH,
        auto_approve=False,
        requires_backup=True
    ),
    RiskRule(
        name="auth_modification",
        keywords=["authentication", "authorization", "permissions", "jwt", "oauth", "login"],
        risk_level=RiskLevel.MEDIUM,
        auto_approve=False
    ),
    RiskRule(
        name="api_breaking_change",
        keywords=["breaking change", "api version", "deprecate endpoint"],
        risk_level=RiskLevel.HIGH,
        auto_approve=False
    ),
    RiskRule(
        name="config_change",
        keywords=["config", "environment", "settings", ".env"],
        risk_level=RiskLevel.MEDIUM,
        auto_approve=True
    ),
    RiskRule(
        name="documentation",
        keywords=["readme", "docs", "documentation", "comment"],
        risk_level=RiskLevel.LOW,
        auto_approve=True
    ),
    RiskRule(
        name="testing",
        keywords=["test", "spec", "unittest", "integration test"],
        risk_level=RiskLevel.LOW,
        auto_approve=True
    ),
]


@dataclass
class ImpactAnalysis:
    """Analysis of feature impact."""
    files_to_modify: List[str] = field(default_factory=list)
    new_dependencies: List[str] = field(default_factory=list)
    environment_variables: List[str] = field(default_factory=list)
    database_changes: bool = False
    api_changes: bool = False
    rollback_difficulty: str = "easy"  # easy | medium | hard


@dataclass
class Alternative:
    """Alternative approach to feature implementation."""
    id: str
    approach: str
    pros: List[str]
    cons: List[str]


@dataclass
class ApprovalRequest:
    """Approval request for high-risk feature."""
    id: str
    created_at: str
    feature_id: str
    feature_description: str
    risk_level: RiskLevel
    status: ApprovalStatus
    impact: ImpactAnalysis
    proposed_changes: str
    alternatives: List[Alternative]
    timeout_at: str
    resolved_at: Optional[str] = None
    resolved_by: Optional[str] = None
    notes: Optional[str] = None


@dataclass
class RiskAssessment:
    """Risk assessment result."""
    level: RiskLevel
    requires_approval: bool
    matched_rules: List[str]
    confidence: float
    reasoning: str


class RiskAssessor:
    """
    Assesses feature risk level based on description and analysis.
    """

    def __init__(self):
        self.rules = RISK_RULES

    def assess_feature(self, description: str, tags: List[str] = None) -> RiskAssessment:
        """
        Classify feature risk level.

        Returns RiskAssessment with level and approval requirement.
        """
        tags = tags or []
        text = f"{description} {' '.join(tags)}".lower()

        matched_rules = []
        highest_risk = RiskLevel.LOW

        # Match against rules
        for rule in self.rules:
            for keyword in rule.keywords:
                if keyword in text:
                    matched_rules.append(rule.name)
                    if self._risk_higher(rule.risk_level, highest_risk):
                        highest_risk = rule.risk_level
                    break

        if not matched_rules:
            # No specific rule - use heuristic
            risk_score = self._calculate_heuristic_risk(description, tags)
            if risk_score > 0.7:
                highest_risk = RiskLevel.HIGH
            elif risk_score > 0.4:
                highest_risk = RiskLevel.MEDIUM
            confidence = 0.6
            reasoning = "Heuristic risk assessment (no specific rules matched)"
        else:
            confidence = 0.9
            reasoning = f"Matched rules: {', '.join(matched_rules)}"

        # Determine if approval required
        requires_approval = False
        if highest_risk in [RiskLevel.HIGH, RiskLevel.MEDIUM]:
            # Check if any matched rule requires approval
            for rule in self.rules:
                if rule.name in matched_rules and not rule.auto_approve:
                    requires_approval = True
                    break

        return RiskAssessment(
            level=highest_risk,
            requires_approval=requires_approval,
            matched_rules=matched_rules,
            confidence=confidence,
            reasoning=reasoning
        )

    def _risk_higher(self, risk1: RiskLevel, risk2: RiskLevel) -> bool:
        """Compare risk levels."""
        order = {RiskLevel.LOW: 0, RiskLevel.MEDIUM: 1, RiskLevel.HIGH: 2}
        return order[risk1] > order[risk2]

    def _calculate_heuristic_risk(self, description: str, tags: List[str]) -> float:
        """Calculate risk score using heuristics."""
        risk_score = 0.3  # Base score

        # Increase for certain keywords
        high_risk_words = ["delete", "remove", "drop", "destroy", "production", "critical"]
        for word in high_risk_words:
            if word in description.lower():
                risk_score += 0.15

        # Increase for database-related
        if any(db in description.lower() for db in ["database", "sql", "schema"]):
            risk_score += 0.1

        # Increase for auth-related
        if any(auth in description.lower() for auth in ["auth", "login", "permission"]):
            risk_score += 0.1

        return min(risk_score, 1.0)


class ApprovalQueue:
    """
    Manages approval requests and workflow.

    Stores requests in .claude/approval-queue.json
    """

    def __init__(self, project_dir: str = "."):
        self.project_dir = Path(project_dir)
        self.queue_path = self.project_dir / ".claude" / "approval-queue.json"
        self.queue_path.parent.mkdir(exist_ok=True)

        self.pending: List[ApprovalRequest] = []
        self.resolved: List[ApprovalRequest] = []

        self._load()

    def _load(self):
        """Load queue from disk."""
        if not self.queue_path.exists():
            self._save()
            return

        try:
            with open(self.queue_path, 'r') as f:
                data = json.load(f)

            self.pending = [
                ApprovalRequest(
                    **{**req, "risk_level": RiskLevel(req["risk_level"]), "status": ApprovalStatus(req["status"])},
                    impact=ImpactAnalysis(**req["impact"]),
                    alternatives=[Alternative(**alt) for alt in req["alternatives"]]
                )
                for req in data.get("pending_approvals", [])
            ]

            self.resolved = [
                ApprovalRequest(
                    **{**req, "risk_level": RiskLevel(req["risk_level"]), "status": ApprovalStatus(req["status"])},
                    impact=ImpactAnalysis(**req["impact"]),
                    alternatives=[Alternative(**alt) for alt in req["alternatives"]]
                )
                for req in data.get("resolved_approvals", [])
            ]

            logger.info(f"Loaded approval queue: {len(self.pending)} pending, {len(self.resolved)} resolved")

        except Exception as e:
            logger.error(f"Failed to load approval queue: {e}")

    def _save(self):
        """Save queue to disk."""
        try:
            # Convert to serializable format
            def serialize_request(req: ApprovalRequest) -> dict:
                data = asdict(req)
                data["risk_level"] = req.risk_level.value
                data["status"] = req.status.value
                return data

            data = {
                "version": "2.0.0",
                "pending_approvals": [serialize_request(r) for r in self.pending],
                "resolved_approvals": [serialize_request(r) for r in self.resolved]
            }

            with open(self.queue_path, 'w') as f:
                json.dump(data, f, indent=2)

            logger.debug("Saved approval queue")

        except Exception as e:
            logger.error(f"Failed to save approval queue: {e}")

    def create_request(
        self,
        feature_id: str,
        feature_description: str,
        risk_assessment: RiskAssessment,
        impact: ImpactAnalysis,
        proposed_changes: str = "",
        timeout_hours: int = 24
    ) -> ApprovalRequest:
        """Create new approval request."""
        request_id = str(uuid.uuid4())[:8]

        # Generate alternatives (placeholder - could be AI-generated)
        alternatives = self._generate_alternatives(feature_description, risk_assessment)

        request = ApprovalRequest(
            id=request_id,
            created_at=datetime.now(timezone.utc).isoformat(),
            feature_id=feature_id,
            feature_description=feature_description,
            risk_level=risk_assessment.level,
            status=ApprovalStatus.PENDING,
            impact=impact,
            proposed_changes=proposed_changes,
            alternatives=alternatives,
            timeout_at=(datetime.now(timezone.utc) + timedelta(hours=timeout_hours)).isoformat()
        )

        self.pending.append(request)
        self._save()

        # Create notification
        self._create_notification(request)

        logger.info(f"📋 Created approval request {request_id} for {feature_description[:50]}...")

        return request

    def _generate_alternatives(
        self,
        feature_description: str,
        risk_assessment: RiskAssessment
    ) -> List[Alternative]:
        """Generate alternative approaches (placeholder for Phase 2)."""
        # In full implementation, this could use AI to suggest alternatives
        # For now, return generic alternatives based on risk level

        alternatives = []

        if risk_assessment.level == RiskLevel.HIGH:
            alternatives.append(Alternative(
                id="alt-001",
                approach="Implement in phases with incremental rollout",
                pros=["Lower risk per phase", "Easier rollback", "Gradual testing"],
                cons=["Takes longer", "More complex coordination"]
            ))

            alternatives.append(Alternative(
                id="alt-002",
                approach="Create feature flag for controlled activation",
                pros=["Can disable quickly", "Controlled rollout", "A/B testing possible"],
                cons=["Additional complexity", "Technical debt from flags"]
            ))

        return alternatives

    def _create_notification(self, request: ApprovalRequest):
        """Create notification file for user."""
        notification_path = self.project_dir / ".claude" / "notification.txt"

        message = f"""
⚠️  APPROVAL REQUIRED

Feature: {request.feature_description}
Risk Level: {request.risk_level.value.upper()}
Request ID: {request.id}

Impact:
  Files to modify: {len(request.impact.files_to_modify)}
  New dependencies: {len(request.impact.new_dependencies)}
  Database changes: {'Yes' if request.impact.database_changes else 'No'}
  Rollback difficulty: {request.impact.rollback_difficulty}

Proposed Changes:
{request.proposed_changes[:200] if request.proposed_changes else 'Not specified'}

Alternatives Available: {len(request.alternatives)}

Review and approve with:
  /sdk-bridge:approve {request.id}

Or reject with alternative:
  /sdk-bridge:reject {request.id} --alternative=<alt-id>

Timeout: {request.timeout_at}
"""

        with open(notification_path, 'w') as f:
            f.write(message)

        logger.info(f"📢 Notification created: {notification_path}")

    def approve(self, request_id: str, notes: str = "") -> bool:
        """Approve pending request."""
        for i, req in enumerate(self.pending):
            if req.id == request_id:
                req.status = ApprovalStatus.APPROVED
                req.resolved_at = datetime.now(timezone.utc).isoformat()
                req.resolved_by = "user"
                req.notes = notes

                self.resolved.append(req)
                del self.pending[i]

                self._save()
                logger.info(f"✅ Approved request {request_id}")
                return True

        logger.warning(f"⚠️  Request {request_id} not found in pending queue")
        return False

    def reject(self, request_id: str, alternative_id: str = None, notes: str = "") -> bool:
        """Reject pending request."""
        for i, req in enumerate(self.pending):
            if req.id == request_id:
                req.status = ApprovalStatus.REJECTED
                req.resolved_at = datetime.now(timezone.utc).isoformat()
                req.resolved_by = "user"
                req.notes = notes

                if alternative_id:
                    req.notes = f"{notes}\nAlternative selected: {alternative_id}"

                self.resolved.append(req)
                del self.pending[i]

                self._save()
                logger.info(f"❌ Rejected request {request_id}")
                return True

        logger.warning(f"⚠️  Request {request_id} not found in pending queue")
        return False

    def get_pending(self) -> List[ApprovalRequest]:
        """Get all pending requests."""
        return self.pending.copy()

    def get_request(self, request_id: str) -> Optional[ApprovalRequest]:
        """Get specific request by ID."""
        for req in self.pending + self.resolved:
            if req.id == request_id:
                return req
        return None


# CLI for testing
if __name__ == "__main__":
    import sys

    logging.basicConfig(level=logging.INFO)

    assessor = RiskAssessor()
    queue = ApprovalQueue()

    # Test scenarios
    scenarios = [
        ("Add DROP COLUMN migration to remove legacy field", ["database", "migration"]),
        ("Update README with new installation instructions", ["docs"]),
        ("Implement JWT authentication middleware", ["auth", "security"]),
        ("Add unit tests for user service", ["testing"]),
    ]

    print("🧪 Testing Risk Assessment & Approval System\n")

    for desc, tags in scenarios:
        print(f"Feature: {desc}")
        print(f"Tags: {', '.join(tags)}")

        assessment = assessor.assess_feature(desc, tags)

        print(f"  Risk Level: {assessment.level.value.upper()}")
        print(f"  Requires Approval: {'Yes' if assessment.requires_approval else 'No'}")
        print(f"  Confidence: {assessment.confidence:.0%}")
        print(f"  Reasoning: {assessment.reasoning}")

        if assessment.requires_approval:
            impact = ImpactAnalysis(
                files_to_modify=["example.py"],
                database_changes=any(r in assessment.matched_rules for r in ["database_migration", "data_deletion"]),
                rollback_difficulty="high" if assessment.level == RiskLevel.HIGH else "medium"
            )

            request = queue.create_request(
                feature_id=f"feat-{len(queue.pending) + 1}",
                feature_description=desc,
                risk_assessment=assessment,
                impact=impact,
                proposed_changes="Example changes..."
            )

            print(f"  → Created approval request: {request.id}")

        print()

    print(f"📋 Total pending approvals: {len(queue.get_pending())}")
