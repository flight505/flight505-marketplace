#!/usr/bin/env python3
"""
Semantic Memory System - SDK Bridge v2.0

Cross-project learning system that stores and retrieves solutions from past
feature implementations using vector similarity search.

Features:
- SQLite-based knowledge graph
- Vector embeddings for semantic search
- Privacy-preserving (local-first)
- Pattern extraction from successful implementations

Author: SDK Bridge Team
Version: 2.0.0-alpha
"""

import json
import logging
import os
import sqlite3
from dataclasses import dataclass, field, asdict
from datetime import datetime
from pathlib import Path
from typing import List, Optional, Dict, Any
import hashlib


# Configure logging
logger = logging.getLogger("semantic_memory")


@dataclass
class Feature:
    """Represents a feature to implement."""
    description: str
    tags: List[str] = field(default_factory=list)
    risk_score: float = 0.5
    complexity: float = 0.5
    id: Optional[str] = None

    def __post_init__(self):
        if self.id is None:
            # Generate ID from description
            self.id = hashlib.md5(self.description.encode()).hexdigest()[:12]


@dataclass
class Solution:
    """Represents a solution to a feature."""
    approach: str
    patterns: List[str] = field(default_factory=list)
    files_modified: List[str] = field(default_factory=list)
    outcome: str = "success"  # success | partial | failed


@dataclass
class ExecutionResult:
    """Result of feature execution."""
    success: bool
    message: str
    commit_hash: Optional[str] = None
    model: str = "claude-sonnet-4-5-20250929"
    quality_score: float = 0.0


@dataclass
class SimilarFeature:
    """Similar feature from semantic search."""
    description: str
    tags: List[str]
    similarity: float
    approach: str
    patterns: List[str]
    success_score: float


class SemanticMemory:
    """
    Cross-project learning system with vector search.

    Phase 1 Implementation:
    - Basic SQLite storage
    - Simple text similarity (TF-IDF or keyword matching)
    - Pattern storage and retrieval

    Future: Replace with proper vector embeddings (Claude Embeddings API)
    """

    def __init__(self, db_path: Optional[str] = None):
        if db_path is None:
            # Default to global location
            db_dir = Path.home() / ".claude" / "sdk-bridge-v2"
            db_dir.mkdir(parents=True, exist_ok=True)
            db_path = str(db_dir / "semantic-memory.db")

        self.db_path = db_path
        self.conn = sqlite3.connect(db_path)
        self.conn.row_factory = sqlite3.Row  # Access columns by name

        self._initialize_schema()
        logger.info(f"Semantic memory initialized: {db_path}")

    def _initialize_schema(self):
        """Create database schema if not exists."""
        cursor = self.conn.cursor()

        # Features table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS features (
                id TEXT PRIMARY KEY,
                description TEXT NOT NULL,
                tags TEXT,
                risk_score REAL,
                complexity_score REAL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                project_hash TEXT
            )
        """)

        # Solutions table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS solutions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                feature_id TEXT REFERENCES features(id),
                approach TEXT,
                code_patterns TEXT,
                files_modified TEXT,
                outcome TEXT,
                model_used TEXT,
                session_count INTEGER DEFAULT 1,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        # Feature-Solution relationships with success scores
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS feature_solutions (
                feature_id TEXT REFERENCES features(id),
                solution_id INTEGER REFERENCES solutions(id),
                success_score REAL,
                PRIMARY KEY (feature_id, solution_id)
            )
        """)

        # Patterns library
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS patterns (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT UNIQUE,
                description TEXT,
                applicability TEXT,
                code_template TEXT,
                success_rate REAL DEFAULT 0.0,
                usage_count INTEGER DEFAULT 0,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        # Errors table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS errors (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                feature_id TEXT REFERENCES features(id),
                solution_id INTEGER REFERENCES solutions(id),
                error_type TEXT,
                message TEXT,
                context TEXT,
                resolved_by TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        # Create indices for performance
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_features_tags
            ON features(tags)
        """)

        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_solutions_outcome
            ON solutions(outcome)
        """)

        self.conn.commit()
        logger.debug("Schema initialized successfully")

    def _simple_similarity(self, text1: str, text2: str) -> float:
        """
        Simple text similarity using word overlap.

        Phase 1: Basic keyword matching
        Future: Replace with vector embeddings and cosine similarity
        """
        # Convert to lowercase and split into words
        words1 = set(text1.lower().split())
        words2 = set(text2.lower().split())

        # Jaccard similarity
        intersection = words1.intersection(words2)
        union = words1.union(words2)

        if len(union) == 0:
            return 0.0

        return len(intersection) / len(union)

    async def find_similar_features(
        self,
        feature: Feature,
        limit: int = 5
    ) -> List[SimilarFeature]:
        """
        Find similar features from past implementations.

        Phase 1: Simple keyword matching
        Future: Vector similarity search with embeddings
        """
        cursor = self.conn.cursor()

        # Get all successful features
        cursor.execute("""
            SELECT
                f.id,
                f.description,
                f.tags,
                s.approach,
                s.code_patterns,
                fs.success_score
            FROM features f
            JOIN feature_solutions fs ON f.id = fs.feature_id
            JOIN solutions s ON fs.solution_id = s.id
            WHERE s.outcome = 'success'
        """)

        results = []
        for row in cursor.fetchall():
            # Calculate similarity
            similarity = self._simple_similarity(
                feature.description,
                row['description']
            )

            if similarity > 0.1:  # Minimum threshold
                results.append(SimilarFeature(
                    description=row['description'],
                    tags=json.loads(row['tags']) if row['tags'] else [],
                    similarity=similarity,
                    approach=row['approach'] or "",
                    patterns=json.loads(row['code_patterns']) if row['code_patterns'] else [],
                    success_score=row['success_score'] or 0.0
                ))

        # Sort by similarity and return top-k
        results.sort(key=lambda x: x.similarity, reverse=True)
        return results[:limit]

    async def store_success(
        self,
        feature: Feature,
        solution: Solution,
        execution_result: ExecutionResult
    ):
        """Store successful execution for future learning."""
        cursor = self.conn.cursor()

        try:
            # Store feature
            cursor.execute("""
                INSERT OR REPLACE INTO features
                (id, description, tags, risk_score, complexity_score, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (
                feature.id,
                feature.description,
                json.dumps(feature.tags),
                feature.risk_score,
                feature.complexity,
                datetime.utcnow().isoformat()
            ))

            # Store solution
            cursor.execute("""
                INSERT INTO solutions
                (feature_id, approach, code_patterns, files_modified, outcome, model_used)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (
                feature.id,
                solution.approach,
                json.dumps(solution.patterns),
                json.dumps(solution.files_modified),
                solution.outcome,
                execution_result.model
            ))

            solution_id = cursor.lastrowid

            # Store relationship
            cursor.execute("""
                INSERT INTO feature_solutions
                (feature_id, solution_id, success_score)
                VALUES (?, ?, ?)
            """, (feature.id, solution_id, execution_result.quality_score))

            self.conn.commit()
            logger.info(f"✅ Stored success in semantic memory: {feature.description[:50]}...")

        except Exception as e:
            self.conn.rollback()
            logger.error(f"❌ Failed to store in semantic memory: {e}")
            raise

    async def store_error(
        self,
        feature: Feature,
        error_type: str,
        message: str,
        context: str = ""
    ):
        """Store error for learning from failures."""
        cursor = self.conn.cursor()

        try:
            # Ensure feature exists
            cursor.execute("""
                INSERT OR IGNORE INTO features
                (id, description, tags, created_at)
                VALUES (?, ?, ?, ?)
            """, (
                feature.id,
                feature.description,
                json.dumps(feature.tags),
                datetime.utcnow().isoformat()
            ))

            # Store error
            cursor.execute("""
                INSERT INTO errors
                (feature_id, error_type, message, context)
                VALUES (?, ?, ?, ?)
            """, (feature.id, error_type, message, context))

            self.conn.commit()
            logger.debug(f"📝 Stored error: {error_type}")

        except Exception as e:
            self.conn.rollback()
            logger.error(f"❌ Failed to store error: {e}")

    async def get_statistics(self) -> Dict[str, Any]:
        """Get semantic memory statistics."""
        cursor = self.conn.cursor()

        stats = {}

        # Total features
        cursor.execute("SELECT COUNT(*) as count FROM features")
        stats['total_features'] = cursor.fetchone()['count']

        # Total solutions
        cursor.execute("SELECT COUNT(*) as count FROM solutions")
        stats['total_solutions'] = cursor.fetchone()['count']

        # Success rate
        cursor.execute("""
            SELECT
                outcome,
                COUNT(*) as count
            FROM solutions
            GROUP BY outcome
        """)
        outcomes = {row['outcome']: row['count'] for row in cursor.fetchall()}
        total_outcomes = sum(outcomes.values())
        stats['success_rate'] = outcomes.get('success', 0) / total_outcomes if total_outcomes > 0 else 0.0

        # Most common patterns
        cursor.execute("""
            SELECT name, usage_count, success_rate
            FROM patterns
            ORDER BY usage_count DESC
            LIMIT 5
        """)
        stats['top_patterns'] = [
            {
                'name': row['name'],
                'usage_count': row['usage_count'],
                'success_rate': row['success_rate']
            }
            for row in cursor.fetchall()
        ]

        return stats

    def export_knowledge(self, output_path: str):
        """Export knowledge graph for sharing with team (privacy-preserving)."""
        cursor = self.conn.cursor()

        # Export only patterns and anonymized statistics
        cursor.execute("SELECT * FROM patterns")
        patterns = [dict(row) for row in cursor.fetchall()]

        cursor.execute("""
            SELECT
                outcome,
                COUNT(*) as count,
                AVG(success_score) as avg_score
            FROM solutions s
            JOIN feature_solutions fs ON s.id = fs.solution_id
            GROUP BY outcome
        """)
        statistics = [dict(row) for row in cursor.fetchall()]

        export_data = {
            "version": "2.0.0",
            "exported_at": datetime.utcnow().isoformat(),
            "patterns": patterns,
            "statistics": statistics
        }

        with open(output_path, 'w') as f:
            json.dump(export_data, f, indent=2)

        logger.info(f"📤 Knowledge exported to {output_path}")

    def import_knowledge(self, input_path: str):
        """Import knowledge from team export."""
        with open(input_path, 'r') as f:
            data = json.load(f)

        cursor = self.conn.cursor()

        # Import patterns
        for pattern in data.get('patterns', []):
            cursor.execute("""
                INSERT OR REPLACE INTO patterns
                (name, description, applicability, code_template, success_rate, usage_count)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (
                pattern['name'],
                pattern['description'],
                pattern['applicability'],
                pattern['code_template'],
                pattern['success_rate'],
                pattern['usage_count']
            ))

        self.conn.commit()
        logger.info(f"📥 Knowledge imported from {input_path}")

    def close(self):
        """Close database connection."""
        if self.conn:
            self.conn.close()
            logger.debug("Database connection closed")

    def __enter__(self):
        """Context manager entry."""
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        self.close()


# CLI for testing
if __name__ == "__main__":
    import asyncio

    async def test_semantic_memory():
        """Test semantic memory functionality."""
        print("🧪 Testing Semantic Memory System\n")

        # Initialize
        memory = SemanticMemory()

        # Create test feature
        feature = Feature(
            description="Add JWT authentication to Express.js API",
            tags=["auth", "security", "express"],
            risk_score=0.7,
            complexity=0.6
        )

        # Store success
        solution = Solution(
            approach="Used jsonwebtoken library with bcrypt for password hashing",
            patterns=["jwt-middleware", "bcrypt-hashing"],
            files_modified=["src/auth/jwt.ts", "src/middleware/auth.ts"]
        )

        result = ExecutionResult(
            success=True,
            message="Feature completed successfully",
            model="claude-sonnet-4-5-20250929",
            quality_score=0.85
        )

        await memory.store_success(feature, solution, result)
        print("✅ Stored success\n")

        # Find similar
        similar_feature = Feature(
            description="Implement authentication with JWT tokens",
            tags=["auth", "jwt"],
            risk_score=0.6,
            complexity=0.5
        )

        similar = await memory.find_similar_features(similar_feature, limit=3)
        print(f"🔍 Found {len(similar)} similar features:")
        for sim in similar:
            print(f"  - {sim.description[:60]}... (similarity: {sim.similarity:.0%})")
            print(f"    Approach: {sim.approach[:80]}...")
        print()

        # Get statistics
        stats = await memory.get_statistics()
        print("📊 Statistics:")
        print(f"  Total features: {stats['total_features']}")
        print(f"  Total solutions: {stats['total_solutions']}")
        print(f"  Success rate: {stats['success_rate']:.0%}")
        print()

        # Export knowledge
        memory.export_knowledge("/tmp/sdk-bridge-knowledge.json")
        print("📤 Knowledge exported\n")

        memory.close()

    asyncio.run(test_semantic_memory())
