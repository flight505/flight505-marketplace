#!/usr/bin/env python3
"""
Dependency Graph Analyzer - SDK Bridge v2.0 Phase 3

Analyzes features to build dependency graph and determine parallel execution order.

Features:
- Dependency detection from feature descriptions
- Topological sorting for execution levels
- Parallel execution planning
- Critical path analysis

Author: SDK Bridge Team
Version: 2.0.0-alpha (Phase 3)
"""

import json
import logging
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Set, Optional, Tuple


logger = logging.getLogger("dependency_graph")


@dataclass
class FeatureNode:
    """Node in the dependency graph."""
    id: str
    description: str
    tags: List[str] = field(default_factory=list)
    priority: int = 50
    risk_score: float = 0.5
    complexity: float = 0.5
    passes: bool = False
    dependencies: List[str] = field(default_factory=list)  # IDs of features this depends on
    dependents: List[str] = field(default_factory=list)  # IDs of features that depend on this


@dataclass
class ExecutionLevel:
    """Level in parallel execution plan."""
    level: int
    features: List[str]  # Feature IDs
    max_parallelism: int
    estimated_duration_minutes: int = 15


@dataclass
class ExecutionPlan:
    """Complete parallel execution plan."""
    levels: List[ExecutionLevel]
    total_features: int
    max_parallel_workers: int
    estimated_total_minutes: int
    critical_path: List[str]  # Feature IDs on critical path


class DependencyGraph:
    """
    Builds and analyzes dependency graph for features.

    Detects dependencies from:
    1. Explicit 'dependencies' field in feature JSON
    2. Implicit dependencies from descriptions (e.g., "requires auth")
    3. File-based dependencies (features modifying same files)
    """

    def __init__(self):
        self.nodes: Dict[str, FeatureNode] = {}
        self.edges: List[Tuple[str, str]] = []  # (from_id, to_id)

    def add_feature(self, feature: Dict) -> str:
        """Add feature to graph."""
        feature_id = feature.get("id", f"feat-{len(self.nodes) + 1}")

        node = FeatureNode(
            id=feature_id,
            description=feature["description"],
            tags=feature.get("tags", []),
            priority=feature.get("priority", 50),
            risk_score=feature.get("risk_score", 0.5),
            complexity=feature.get("complexity", 0.5),
            passes=feature.get("passes", False),
            dependencies=feature.get("dependencies", [])
        )

        self.nodes[feature_id] = node

        # Add explicit dependency edges
        for dep_id in node.dependencies:
            self.add_edge(dep_id, feature_id)

        return feature_id

    def add_edge(self, from_id: str, to_id: str):
        """Add dependency edge (from_id must complete before to_id)."""
        if (from_id, to_id) not in self.edges:
            self.edges.append((from_id, to_id))

            # Update node references
            if from_id in self.nodes:
                self.nodes[from_id].dependents.append(to_id)
            if to_id in self.nodes:
                if from_id not in self.nodes[to_id].dependencies:
                    self.nodes[to_id].dependencies.append(from_id)

    def detect_implicit_dependencies(self):
        """
        Detect implicit dependencies from feature descriptions.

        Rules:
        - Auth features must complete before protected resource features
        - Database setup must complete before features using that table
        - API setup must complete before features calling that API
        """
        auth_features = []
        db_setup_features = []
        api_features = []

        # Categorize features
        for node_id, node in self.nodes.items():
            desc_lower = node.description.lower()
            tags_lower = [t.lower() for t in node.tags]

            # Auth features
            if any(keyword in desc_lower for keyword in ["authentication", "login", "auth", "jwt", "oauth"]):
                if any(keyword in desc_lower for keyword in ["setup", "implement", "add", "create"]):
                    auth_features.append(node_id)

            # Database setup
            if any(keyword in desc_lower for keyword in ["create table", "database setup", "schema", "migration"]):
                db_setup_features.append(node_id)

            # API features
            if "api" in tags_lower or "endpoint" in desc_lower:
                api_features.append(node_id)

        # Add implicit dependencies
        for node_id, node in self.nodes.items():
            desc_lower = node.description.lower()

            # Features requiring auth depend on auth setup
            if any(keyword in desc_lower for keyword in ["requires auth", "protected", "authenticated"]):
                for auth_id in auth_features:
                    if auth_id != node_id:
                        self.add_edge(auth_id, node_id)
                        logger.debug(f"Implicit dependency: {node_id} requires {auth_id} (auth)")

            # Features using database depend on db setup
            if any(keyword in desc_lower for keyword in ["database", "query", "insert", "update", "delete"]):
                for db_id in db_setup_features:
                    if db_id != node_id and db_id not in node.dependencies:
                        self.add_edge(db_id, node_id)
                        logger.debug(f"Implicit dependency: {node_id} requires {db_id} (database)")

    def topological_sort(self) -> List[List[str]]:
        """
        Topological sort to get execution levels.

        Returns list of levels, where each level contains features
        that can execute in parallel.
        """
        # Calculate in-degree for each node
        in_degree = {node_id: 0 for node_id in self.nodes}

        for from_id, to_id in self.edges:
            if to_id in in_degree:
                in_degree[to_id] += 1

        # Find nodes with no dependencies (in-degree = 0)
        levels = []
        remaining = set(self.nodes.keys())

        while remaining:
            # Current level: nodes with no remaining dependencies
            current_level = [
                node_id for node_id in remaining
                if in_degree[node_id] == 0
            ]

            if not current_level:
                # Cycle detected or isolated nodes
                logger.warning(f"Cycle or isolated nodes detected. Remaining: {remaining}")
                # Add remaining as final level
                current_level = list(remaining)

            levels.append(current_level)

            # Remove current level nodes
            for node_id in current_level:
                remaining.remove(node_id)

                # Decrease in-degree for dependents
                for dependent_id in self.nodes[node_id].dependents:
                    if dependent_id in in_degree:
                        in_degree[dependent_id] -= 1

            if not current_level:
                break

        return levels

    def create_execution_plan(self, max_parallel_workers: int = 3) -> ExecutionPlan:
        """
        Create parallel execution plan.

        Returns ExecutionPlan with levels and parallelism constraints.
        """
        levels_raw = self.topological_sort()

        execution_levels = []
        total_minutes = 0

        for level_idx, feature_ids in enumerate(levels_raw):
            # Calculate parallelism for this level
            parallelism = min(len(feature_ids), max_parallel_workers)

            # Estimate duration (15 min per feature, divided by parallelism)
            duration = int((len(feature_ids) * 15) / parallelism)
            total_minutes += duration

            execution_levels.append(ExecutionLevel(
                level=level_idx,
                features=feature_ids,
                max_parallelism=parallelism,
                estimated_duration_minutes=duration
            ))

        # Calculate critical path (longest path through graph)
        critical_path = self._calculate_critical_path()

        return ExecutionPlan(
            levels=execution_levels,
            total_features=len(self.nodes),
            max_parallel_workers=max_parallel_workers,
            estimated_total_minutes=total_minutes,
            critical_path=critical_path
        )

    def _calculate_critical_path(self) -> List[str]:
        """Calculate critical path (longest path through graph)."""
        # Simple implementation: find longest chain
        def get_chain_length(node_id: str, visited: Set[str]) -> Tuple[int, List[str]]:
            if node_id in visited:
                return 0, []

            visited.add(node_id)

            if not self.nodes[node_id].dependents:
                return 1, [node_id]

            max_length = 0
            max_path = []

            for dependent_id in self.nodes[node_id].dependents:
                length, path = get_chain_length(dependent_id, visited.copy())
                if length > max_length:
                    max_length = length
                    max_path = path

            return max_length + 1, [node_id] + max_path

        # Find root nodes (no dependencies)
        root_nodes = [
            node_id for node_id, node in self.nodes.items()
            if not node.dependencies
        ]

        max_length = 0
        critical_path = []

        for root_id in root_nodes:
            length, path = get_chain_length(root_id, set())
            if length > max_length:
                max_length = length
                critical_path = path

        return critical_path

    def visualize_ascii(self) -> str:
        """Generate ASCII visualization of dependency graph."""
        lines = ["Dependency Graph:", "=" * 50, ""]

        levels = self.topological_sort()

        for level_idx, feature_ids in enumerate(levels):
            lines.append(f"Level {level_idx}:")
            for feature_id in feature_ids:
                node = self.nodes[feature_id]
                deps_str = f" (depends on: {', '.join(node.dependencies)})" if node.dependencies else ""
                lines.append(f"  [{feature_id}] {node.description[:50]}{deps_str}")
            lines.append("")

        return "\n".join(lines)

    def to_json(self) -> Dict:
        """Export graph to JSON format."""
        nodes_data = []
        for node_id, node in self.nodes.items():
            nodes_data.append({
                "id": node.id,
                "description": node.description,
                "tags": node.tags,
                "priority": node.priority,
                "risk_score": node.risk_score,
                "complexity": node.complexity,
                "dependencies": node.dependencies
            })

        edges_data = [
            {"from": from_id, "to": to_id, "type": "requires"}
            for from_id, to_id in self.edges
        ]

        return {
            "version": "2.0.0",
            "nodes": nodes_data,
            "edges": edges_data,
            "metadata": {
                "total_features": len(self.nodes),
                "total_dependencies": len(self.edges)
            }
        }


def build_graph_from_feature_list(feature_list_path: str) -> DependencyGraph:
    """Build dependency graph from feature_list.json."""
    with open(feature_list_path, 'r') as f:
        features = json.load(f)

    graph = DependencyGraph()

    # Add all features
    for feature in features:
        graph.add_feature(feature)

    # Detect implicit dependencies
    graph.detect_implicit_dependencies()

    logger.info(f"Built graph: {len(graph.nodes)} features, {len(graph.edges)} dependencies")

    return graph


# CLI for testing
if __name__ == "__main__":
    import sys

    logging.basicConfig(level=logging.INFO)

    # Test with sample features
    sample_features = [
        {
            "id": "feat-001",
            "description": "Set up Express.js server",
            "tags": ["backend", "setup"],
            "priority": 10,
            "passes": False
        },
        {
            "id": "feat-002",
            "description": "Add JWT authentication middleware",
            "tags": ["auth", "security"],
            "priority": 8,
            "passes": False,
            "dependencies": ["feat-001"]
        },
        {
            "id": "feat-003",
            "description": "Create user registration endpoint (requires auth)",
            "tags": ["api", "auth"],
            "priority": 8,
            "passes": False
        },
        {
            "id": "feat-004",
            "description": "Add database schema for users",
            "tags": ["database"],
            "priority": 9,
            "passes": False,
            "dependencies": ["feat-001"]
        },
        {
            "id": "feat-005",
            "description": "Implement user profile API (protected endpoint)",
            "tags": ["api"],
            "priority": 5,
            "passes": False
        }
    ]

    # Save to temp file
    import tempfile
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        json.dump(sample_features, f)
        temp_path = f.name

    # Build graph
    graph = build_graph_from_feature_list(temp_path)

    print("\n" + graph.visualize_ascii())

    # Create execution plan
    plan = graph.create_execution_plan(max_parallel_workers=3)

    print("\nExecution Plan:")
    print("=" * 50)
    print(f"Total Features: {plan.total_features}")
    print(f"Max Parallel Workers: {plan.max_parallel_workers}")
    print(f"Estimated Duration: {plan.estimated_total_minutes} minutes")
    print(f"Critical Path: {' → '.join(plan.critical_path)}")
    print()

    for level in plan.levels:
        print(f"Level {level.level}: {len(level.features)} feature(s), parallelism={level.max_parallelism}")
        for feat_id in level.features:
            print(f"  - {feat_id}: {graph.nodes[feat_id].description}")
        print()

    # Cleanup
    import os
    os.unlink(temp_path)
