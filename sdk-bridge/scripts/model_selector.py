#!/usr/bin/env python3
"""
Adaptive Model Selection System - SDK Bridge v2.0 Phase 2

Intelligently routes features to optimal models based on:
- Feature complexity and risk scores
- Historical model performance by category
- Cost constraints and budgets
- Learned success patterns

Author: SDK Bridge Team
Version: 2.0.0-alpha (Phase 2)
"""

import json
import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Tuple


logger = logging.getLogger("model_selector")


@dataclass
class ModelConfig:
    """Configuration for available models."""
    name: str
    cost_per_1k_input: float
    cost_per_1k_output: float
    intelligence_score: float  # 0.0-1.0, higher = smarter
    speed_score: float  # 0.0-1.0, higher = faster


# Model configurations (2026 pricing)
AVAILABLE_MODELS = {
    "claude-sonnet-4-5-20250929": ModelConfig(
        name="claude-sonnet-4-5-20250929",
        cost_per_1k_input=0.003,
        cost_per_1k_output=0.015,
        intelligence_score=0.85,
        speed_score=0.95
    ),
    "claude-opus-4-5-20251101": ModelConfig(
        name="claude-opus-4-5-20251101",
        cost_per_1k_input=0.015,
        cost_per_1k_output=0.075,
        intelligence_score=0.98,
        speed_score=0.70
    ),
}


@dataclass
class ModelPerformance:
    """Performance statistics for a model."""
    model_name: str
    total_features: int = 0
    successes: int = 0
    failures: int = 0
    avg_sessions: float = 0.0
    total_cost: float = 0.0
    by_category: Dict[str, Dict[str, float]] = field(default_factory=dict)

    @property
    def success_rate(self) -> float:
        """Calculate overall success rate."""
        if self.total_features == 0:
            return 0.0
        return self.successes / self.total_features

    @property
    def cost_per_feature(self) -> float:
        """Calculate average cost per feature."""
        if self.total_features == 0:
            return 0.0
        return self.total_cost / self.total_features


@dataclass
class SelectionContext:
    """Context for model selection decision."""
    feature_description: str
    tags: List[str] = field(default_factory=list)
    risk_score: float = 0.5
    complexity: float = 0.5
    priority: int = 50
    budget_remaining: Optional[float] = None
    attempt_number: int = 1
    previous_failures: List[str] = field(default_factory=list)


@dataclass
class SelectionResult:
    """Result of model selection."""
    model_name: str
    confidence: float
    reasoning: str
    estimated_cost: float
    fallback_model: Optional[str] = None


class ModelPerformanceTracker:
    """
    Tracks model performance across features and categories.

    Stores data in ~/.claude/sdk-bridge-v2/model-performance.json
    """

    def __init__(self, storage_path: Optional[str] = None):
        if storage_path is None:
            storage_dir = Path.home() / ".claude" / "sdk-bridge-v2"
            storage_dir.mkdir(parents=True, exist_ok=True)
            storage_path = str(storage_dir / "model-performance.json")

        self.storage_path = Path(storage_path)
        self.performance: Dict[str, ModelPerformance] = {}
        self._load()

    def _load(self):
        """Load performance data from disk."""
        if not self.storage_path.exists():
            # Initialize with defaults
            for model_name in AVAILABLE_MODELS.keys():
                self.performance[model_name] = ModelPerformance(model_name=model_name)
            self._save()
            return

        try:
            with open(self.storage_path, 'r') as f:
                data = json.load(f)

            for model_name, perf_data in data.get("models", {}).items():
                self.performance[model_name] = ModelPerformance(
                    model_name=model_name,
                    total_features=perf_data.get("total_features", 0),
                    successes=perf_data.get("successes", 0),
                    failures=perf_data.get("failures", 0),
                    avg_sessions=perf_data.get("avg_sessions_per_feature", 0.0),
                    total_cost=perf_data.get("total_cost", 0.0),
                    by_category=perf_data.get("performance_by_category", {})
                )

            logger.info(f"Loaded performance data for {len(self.performance)} models")

        except Exception as e:
            logger.error(f"Failed to load performance data: {e}")
            # Initialize with defaults
            for model_name in AVAILABLE_MODELS.keys():
                self.performance[model_name] = ModelPerformance(model_name=model_name)

    def _save(self):
        """Save performance data to disk."""
        try:
            data = {
                "version": "2.0.0",
                "last_updated": datetime.now(timezone.utc).isoformat(),
                "models": {}
            }

            for model_name, perf in self.performance.items():
                data["models"][model_name] = {
                    "total_features": perf.total_features,
                    "successes": perf.successes,
                    "failures": perf.failures,
                    "success_rate": perf.success_rate,
                    "avg_sessions_per_feature": perf.avg_sessions,
                    "cost_per_feature_usd": perf.cost_per_feature,
                    "total_cost": perf.total_cost,
                    "performance_by_category": perf.by_category
                }

            with open(self.storage_path, 'w') as f:
                json.dump(data, f, indent=2)

            logger.debug("Saved performance data")

        except Exception as e:
            logger.error(f"Failed to save performance data: {e}")

    def record_success(
        self,
        model_name: str,
        category: str,
        sessions_used: int,
        estimated_cost: float
    ):
        """Record successful feature completion."""
        if model_name not in self.performance:
            self.performance[model_name] = ModelPerformance(model_name=model_name)

        perf = self.performance[model_name]
        perf.total_features += 1
        perf.successes += 1
        perf.total_cost += estimated_cost

        # Update average sessions
        perf.avg_sessions = (
            (perf.avg_sessions * (perf.total_features - 1) + sessions_used)
            / perf.total_features
        )

        # Update category stats
        if category not in perf.by_category:
            perf.by_category[category] = {
                "success_rate": 0.0,
                "avg_sessions": 0.0,
                "count": 0
            }

        cat = perf.by_category[category]
        cat["count"] = cat.get("count", 0) + 1
        cat["success_rate"] = (
            (cat.get("success_rate", 0) * (cat["count"] - 1) + 1.0)
            / cat["count"]
        )
        cat["avg_sessions"] = (
            (cat.get("avg_sessions", 0) * (cat["count"] - 1) + sessions_used)
            / cat["count"]
        )

        self._save()
        logger.info(f"✅ Recorded success: {model_name} on {category}")

    def record_failure(
        self,
        model_name: str,
        category: str,
        sessions_used: int,
        estimated_cost: float
    ):
        """Record feature failure."""
        if model_name not in self.performance:
            self.performance[model_name] = ModelPerformance(model_name=model_name)

        perf = self.performance[model_name]
        perf.total_features += 1
        perf.failures += 1
        perf.total_cost += estimated_cost

        # Update category stats
        if category not in perf.by_category:
            perf.by_category[category] = {
                "success_rate": 0.0,
                "avg_sessions": 0.0,
                "count": 0
            }

        cat = perf.by_category[category]
        cat["count"] = cat.get("count", 0) + 1
        cat["success_rate"] = (
            (cat.get("success_rate", 0) * (cat["count"] - 1) + 0.0)
            / cat["count"]
        )

        self._save()
        logger.info(f"❌ Recorded failure: {model_name} on {category}")

    def get_best_model_for_category(self, category: str) -> Optional[str]:
        """Get model with highest success rate for category."""
        best_model = None
        best_rate = 0.0

        for model_name, perf in self.performance.items():
            if category in perf.by_category:
                rate = perf.by_category[category].get("success_rate", 0.0)
                if rate > best_rate:
                    best_rate = rate
                    best_model = model_name

        return best_model


class AdaptiveModelSelector:
    """
    Selects optimal model for each feature based on:
    - Feature characteristics (complexity, risk, priority)
    - Historical performance data
    - Cost constraints
    - Retry context (escalate on failures)
    """

    def __init__(self, performance_tracker: Optional[ModelPerformanceTracker] = None):
        self.tracker = performance_tracker or ModelPerformanceTracker()
        self.models = AVAILABLE_MODELS

    def _infer_category(self, context: SelectionContext) -> str:
        """Infer feature category from tags and description."""
        # Priority order for categorization
        categories = {
            "auth": ["auth", "authentication", "login", "jwt", "oauth", "security"],
            "database": ["database", "db", "sql", "postgres", "mysql", "migration"],
            "frontend": ["react", "vue", "ui", "component", "css", "html"],
            "backend": ["api", "endpoint", "server", "express", "fastapi"],
            "testing": ["test", "testing", "spec", "unittest"],
            "documentation": ["docs", "documentation", "readme", "guide"],
            "algorithms": ["algorithm", "optimization", "sort", "search"],
        }

        desc_lower = context.feature_description.lower()
        tags_lower = [t.lower() for t in context.tags]

        for category, keywords in categories.items():
            for keyword in keywords:
                if keyword in desc_lower or keyword in tags_lower:
                    return category

        return "general"

    def select_model(self, context: SelectionContext) -> SelectionResult:
        """
        Select optimal model for feature.

        Decision factors:
        1. High risk/complexity → Opus
        2. Low complexity + budget constrained → Sonnet
        3. Retry attempt → Escalate to smarter model
        4. Category performance history → Use best performing model
        5. Cost efficiency → Prefer Sonnet unless needs justify Opus
        """
        category = self._infer_category(context)

        # Rule 1: High risk always gets Opus
        if context.risk_score > 0.7:
            return SelectionResult(
                model_name="claude-opus-4-5-20251101",
                confidence=0.95,
                reasoning=f"High risk ({context.risk_score:.0%}) requires most capable model",
                estimated_cost=self.models["claude-opus-4-5-20251101"].cost_per_1k_input * 2.0,
                fallback_model=None
            )

        # Rule 2: Retry escalation
        if context.attempt_number > 1:
            if "claude-sonnet" in context.previous_failures:
                return SelectionResult(
                    model_name="claude-opus-4-5-20251101",
                    confidence=0.90,
                    reasoning=f"Escalating to Opus after {context.attempt_number - 1} Sonnet failure(s)",
                    estimated_cost=self.models["claude-opus-4-5-20251101"].cost_per_1k_input * 2.0,
                    fallback_model=None
                )

        # Rule 3: Budget constraint
        if context.budget_remaining is not None and context.budget_remaining < 1.0:
            return SelectionResult(
                model_name="claude-sonnet-4-5-20250929",
                confidence=0.80,
                reasoning=f"Budget constrained (${context.budget_remaining:.2f} remaining)",
                estimated_cost=self.models["claude-sonnet-4-5-20250929"].cost_per_1k_input * 2.0,
                fallback_model=None
            )

        # Rule 4: Historical performance for category
        best_model = self.tracker.get_best_model_for_category(category)
        if best_model and best_model in self.models:
            perf = self.tracker.performance[best_model]
            if category in perf.by_category:
                cat_perf = perf.by_category[category]
                success_rate = cat_perf.get("success_rate", 0.0)

                if success_rate > 0.8:  # High confidence threshold
                    return SelectionResult(
                        model_name=best_model,
                        confidence=success_rate,
                        reasoning=f"Best performer for {category} ({success_rate:.0%} success rate)",
                        estimated_cost=self.models[best_model].cost_per_1k_input * 2.0,
                        fallback_model="claude-opus-4-5-20251101" if best_model != "claude-opus-4-5-20251101" else None
                    )

        # Rule 5: Complexity-based default
        if context.complexity > 0.7:
            # High complexity → Opus
            return SelectionResult(
                model_name="claude-opus-4-5-20251101",
                confidence=0.75,
                reasoning=f"High complexity ({context.complexity:.0%}) benefits from Opus",
                estimated_cost=self.models["claude-opus-4-5-20251101"].cost_per_1k_input * 2.0,
                fallback_model=None
            )
        else:
            # Default to Sonnet (cost-effective)
            return SelectionResult(
                model_name="claude-sonnet-4-5-20250929",
                confidence=0.70,
                reasoning="Default to cost-effective Sonnet for standard feature",
                estimated_cost=self.models["claude-sonnet-4-5-20250929"].cost_per_1k_input * 2.0,
                fallback_model="claude-opus-4-5-20251101"
            )


# CLI for testing
if __name__ == "__main__":
    import sys

    logging.basicConfig(level=logging.INFO)

    tracker = ModelPerformanceTracker()
    selector = AdaptiveModelSelector(tracker)

    # Test scenarios
    scenarios = [
        SelectionContext(
            feature_description="Add JWT authentication middleware",
            tags=["auth", "security"],
            risk_score=0.8,
            complexity=0.6,
            priority=100
        ),
        SelectionContext(
            feature_description="Update README documentation",
            tags=["docs"],
            risk_score=0.1,
            complexity=0.2,
            priority=20
        ),
        SelectionContext(
            feature_description="Optimize database query performance",
            tags=["database", "performance"],
            risk_score=0.5,
            complexity=0.8,
            priority=80
        ),
        SelectionContext(
            feature_description="Fix typo in error message",
            tags=["bugfix"],
            risk_score=0.1,
            complexity=0.1,
            priority=10,
            budget_remaining=0.50
        ),
    ]

    print("🧪 Testing Adaptive Model Selection\n")

    for i, ctx in enumerate(scenarios, 1):
        print(f"Scenario {i}: {ctx.feature_description}")
        print(f"  Tags: {', '.join(ctx.tags)}")
        print(f"  Risk: {ctx.risk_score:.0%}, Complexity: {ctx.complexity:.0%}")

        result = selector.select_model(ctx)

        print(f"  → Selected: {result.model_name}")
        print(f"  → Reasoning: {result.reasoning}")
        print(f"  → Confidence: {result.confidence:.0%}")
        print(f"  → Est. Cost: ${result.estimated_cost:.3f}")
        if result.fallback_model:
            print(f"  → Fallback: {result.fallback_model}")
        print()
