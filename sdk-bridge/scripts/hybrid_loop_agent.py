#!/usr/bin/env python3
"""
Hybrid Loop Agent - SDK Bridge v2.0

Combines Ralph Wiggum's same-session self-healing loops with SDK Bridge's
multi-session autonomous execution pattern.

Architecture:
- Outer loop: Multi-session progression (SDK pattern)
- Inner loop: Same-session validation and self-healing (Ralph pattern)

Author: SDK Bridge Team
Version: 2.0.0-alpha
"""

import asyncio
import json
import logging
import os
import sys
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any

# Add semantic memory and Phase 2 modules to path
sys.path.append(os.path.dirname(__file__))
from semantic_memory import SemanticMemory, Feature, Solution, ExecutionResult
from model_selector import AdaptiveModelSelector, ModelPerformanceTracker, SelectionContext
from approval_system import RiskAssessor, ApprovalQueue, RiskLevel, ImpactAnalysis


# Configure logging
def setup_logging(log_level: str = "INFO") -> logging.Logger:
    """Setup structured logging for hybrid agent."""
    logger = logging.getLogger("hybrid_loop_agent")
    logger.setLevel(getattr(logging, log_level.upper()))

    handler = logging.StreamHandler()
    formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    handler.setFormatter(formatter)
    logger.addHandler(handler)

    return logger


@dataclass
class ValidationResult:
    """Result of feature validation."""
    success: bool
    errors: List[str] = field(default_factory=list)
    can_self_heal: bool = False
    quality_score: float = 0.0
    message: str = ""


@dataclass
class RetryStrategy:
    """Strategy for retrying failed features."""
    model: Optional[str] = None
    hint: str = ""
    approach: str = ""
    confidence: float = 0.0
    requires_approval: bool = False


@dataclass
class CheckpointData:
    """Data saved at checkpoint."""
    feature_id: str
    session_num: int
    attempt: int
    timestamp: str
    model_used: str
    partial_result: Optional[str] = None
    validation_errors: List[str] = field(default_factory=list)


class HybridLoopAgent:
    """
    Hybrid execution agent combining Ralph and SDK patterns.

    Ralph Pattern: Tight inner loop for validation and self-healing
    SDK Pattern: Outer loop for feature progression and persistence
    """

    def __init__(
        self,
        project_dir: str = ".",
        model: str = "claude-sonnet-4-5-20250929",
        max_inner_loops: int = 5,
        max_outer_sessions: int = 20,
        log_level: str = "INFO",
        enable_semantic_memory: bool = True,
        enable_adaptive_models: bool = True,
        enable_approval_nodes: bool = True
    ):
        self.project_dir = Path(project_dir).resolve()
        self.model = model
        self.max_inner_loops = max_inner_loops
        self.max_outer_sessions = max_outer_sessions
        self.logger = setup_logging(log_level)

        # Phase 2: Adaptive model selection
        self.enable_adaptive_models = enable_adaptive_models
        self.model_selector = None
        self.performance_tracker = None
        if enable_adaptive_models:
            try:
                self.performance_tracker = ModelPerformanceTracker()
                self.model_selector = AdaptiveModelSelector(self.performance_tracker)
                self.logger.info("✅ Adaptive model selection enabled")
            except Exception as e:
                self.logger.warning(f"⚠️  Adaptive models disabled: {e}")

        # Phase 2: Approval system
        self.enable_approval_nodes = enable_approval_nodes
        self.risk_assessor = None
        self.approval_queue = None
        if enable_approval_nodes:
            try:
                self.risk_assessor = RiskAssessor()
                self.approval_queue = ApprovalQueue(str(self.project_dir))
                self.logger.info("✅ Approval nodes enabled")
            except Exception as e:
                self.logger.warning(f"⚠️  Approval nodes disabled: {e}")

        # State paths
        self.claude_dir = self.project_dir / ".claude"
        self.feature_list_path = self.project_dir / "feature_list.json"
        self.checkpoint_path = self.claude_dir / "checkpoint-v2.json"
        self.progress_log_path = self.project_dir / "claude-progress.txt"
        self.protocol_path = self.project_dir / "CLAUDE.md"

        # Semantic memory
        self.semantic_memory = None
        if enable_semantic_memory:
            try:
                self.semantic_memory = SemanticMemory()
                self.logger.info("✅ Semantic memory enabled")
            except Exception as e:
                self.logger.warning(f"⚠️  Semantic memory disabled: {e}")

        self.logger.info(f"Hybrid Loop Agent initialized in {self.project_dir}")
        self.logger.info(f"Config: inner_loops={max_inner_loops}, outer_sessions={max_outer_sessions}")

    def load_feature_list(self) -> List[Dict[str, Any]]:
        """Load feature list from JSON."""
        if not self.feature_list_path.exists():
            self.logger.error(f"❌ Feature list not found: {self.feature_list_path}")
            return []

        with open(self.feature_list_path, 'r') as f:
            features = json.load(f)

        self.logger.info(f"📋 Loaded {len(features)} features")
        return features

    def save_feature_list(self, features: List[Dict[str, Any]]):
        """Save updated feature list."""
        with open(self.feature_list_path, 'w') as f:
            json.dump(features, f, indent=2)
        self.logger.debug(f"💾 Saved feature list")

    def get_next_feature(self, features: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
        """
        Get next feature to implement.

        Priority order:
        1. Features with priority field (higher first)
        2. Features in original order

        Returns only features where passes=false
        """
        pending = [f for f in features if not f.get("passes", False)]

        if not pending:
            return None

        # Sort by priority if available (higher priority first)
        if any("priority" in f for f in pending):
            pending.sort(key=lambda f: f.get("priority", 0), reverse=True)

        return pending[0]

    def create_checkpoint(
        self,
        feature: Dict[str, Any],
        session_num: int,
        attempt: int,
        validation: ValidationResult
    ):
        """Save checkpoint for crash recovery."""
        checkpoint = CheckpointData(
            feature_id=feature.get("id", feature["description"]),
            session_num=session_num,
            attempt=attempt,
            timestamp=datetime.utcnow().isoformat(),
            model_used=self.model,
            partial_result=None,
            validation_errors=validation.errors
        )

        self.claude_dir.mkdir(exist_ok=True)
        with open(self.checkpoint_path, 'w') as f:
            json.dump(checkpoint.__dict__, f, indent=2)

        self.logger.debug(f"📍 Checkpoint saved: session={session_num}, attempt={attempt}")

    def load_checkpoint(self) -> Optional[CheckpointData]:
        """Load checkpoint if exists."""
        if not self.checkpoint_path.exists():
            return None

        with open(self.checkpoint_path, 'r') as f:
            data = json.load(f)

        return CheckpointData(**data)

    def clear_checkpoint(self):
        """Clear checkpoint after successful completion."""
        if self.checkpoint_path.exists():
            self.checkpoint_path.unlink()
            self.logger.debug("🗑️  Checkpoint cleared")

    async def validate_result(self, feature: Dict[str, Any]) -> ValidationResult:
        """
        Validate feature implementation.

        Checks:
        1. Test criteria from feature definition
        2. Git diff shows changes
        3. No syntax errors (basic check)

        Returns ValidationResult with can_self_heal flag.
        """
        self.logger.info("🔍 Validating feature implementation...")

        # Check if test criteria exists
        test_criteria = feature.get("test", "")

        # Basic validation: check if files were modified
        try:
            result = await asyncio.create_subprocess_exec(
                "git", "diff", "--name-only", "HEAD",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=self.project_dir
            )
            stdout, _ = await result.communicate()
            modified_files = stdout.decode().strip().split('\n')

            if not modified_files or modified_files == ['']:
                return ValidationResult(
                    success=False,
                    errors=["No files modified"],
                    can_self_heal=True,  # Simple error, can retry
                    message="Feature implementation produced no changes"
                )

            self.logger.info(f"📝 Modified files: {len(modified_files)}")

        except Exception as e:
            self.logger.error(f"❌ Validation error: {e}")
            return ValidationResult(
                success=False,
                errors=[str(e)],
                can_self_heal=False
            )

        # If we have test criteria, we'd run tests here
        # For Phase 1, we'll use a simplified success criteria
        if test_criteria:
            self.logger.info(f"✅ Test criteria defined: {test_criteria}")

        # Success criteria: files were modified
        return ValidationResult(
            success=True,
            quality_score=0.8,
            message=f"Feature implemented with {len(modified_files)} file(s) changed"
        )

    async def reflect_on_failure(
        self,
        feature: Dict[str, Any],
        validation: ValidationResult
    ) -> str:
        """
        Generate reflection prompt for same-session retry.

        This is the Ralph pattern - analyze failure and try again.
        """
        reflection = f"""
# Reflection on Previous Attempt

The previous implementation attempt did not pass validation.

**Errors:**
{chr(10).join(f"- {error}" for error in validation.errors)}

**Feature Requirements:**
Description: {feature['description']}
Test: {feature.get('test', 'Not specified')}

**Analysis:**
Please analyze what went wrong and try a different approach.
Make sure to:
1. Address each validation error
2. Verify the test criteria will be met
3. Check for common pitfalls

Try again with the corrected implementation.
"""
        return reflection

    async def execute_session_async(
        self,
        feature: Dict[str, Any],
        session_num: int,
        semantic_hints: Optional[List[str]] = None
    ) -> ExecutionResult:
        """
        Execute one session using Claude Agent SDK.

        This is where we'd call the actual SDK query() function.
        For Phase 1, this is a placeholder that simulates execution.
        """
        from claude_agent_sdk import query, ClaudeAgentOptions

        # Read protocol
        protocol = ""
        if self.protocol_path.exists():
            with open(self.protocol_path, 'r') as f:
                protocol = f.read()

        # Build prompt with semantic hints
        hints_section = ""
        if semantic_hints:
            hints_section = "\n\n## Learned Patterns from Similar Features\n\n"
            hints_section += "\n".join(f"- {hint}" for hint in semantic_hints)

        prompt = f"""
I am working on a project in {self.project_dir}.

{protocol}

{hints_section}

**Current Task:**
Description: {feature['description']}
Test Criteria: {feature.get('test', 'None provided')}

Please implement this feature according to the requirements.
When complete, ensure it meets the test criteria and commit your changes.

Respond with SUCCESS when the feature is fully implemented and tested.
"""

        try:
            # Check for API authentication
            if not os.environ.get("CLAUDE_CODE_OAUTH_TOKEN") and not os.environ.get("ANTHROPIC_API_KEY"):
                self.logger.error("❌ No API key found. Set CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY")
                return ExecutionResult(
                    success=False,
                    message="Authentication required",
                    commit_hash=None
                )

            auth_method = 'CLAUDE_CODE_OAUTH_TOKEN' if os.environ.get('CLAUDE_CODE_OAUTH_TOKEN') else 'ANTHROPIC_API_KEY'
            self.logger.info(f"🔐 Using auth: {auth_method}")

            # Execute SDK session
            options = ClaudeAgentOptions(
                model=self.model,
                max_turns=50,
            )

            result_text = ""
            self.logger.info(f"🤖 Starting SDK session (model: {self.model})...")

            async for message in query(prompt=prompt, options=options):
                if hasattr(message, 'content'):
                    for block in message.content:
                        if hasattr(block, 'text'):
                            result_text += block.text
                            self.logger.debug(f"Agent: {block.text[:100]}...")

            # Analyze result
            success = "SUCCESS" in result_text.upper() or "COMPLETED" in result_text.upper()

            return ExecutionResult(
                success=success,
                message=result_text[:500],  # First 500 chars
                commit_hash=None,  # Would be populated from git
                model=self.model,
                quality_score=0.8 if success else 0.3
            )

        except ImportError as e:
            self.logger.error(f"❌ claude-agent-sdk import failed: {e}")
            return ExecutionResult(
                success=False,
                message=f"SDK import error: {e}",
                commit_hash=None
            )
        except Exception as e:
            self.logger.error(f"❌ Error during agent execution: {str(e)}")
            return ExecutionResult(
                success=False,
                message=str(e),
                commit_hash=None
            )

    def execute_session(self, feature: Dict[str, Any], session_num: int, semantic_hints: Optional[List[str]] = None) -> ExecutionResult:
        """Synchronous wrapper for async execute_session."""
        return asyncio.run(self.execute_session_async(feature, session_num, semantic_hints))

    async def execute_feature(self, feature: Dict[str, Any]) -> ExecutionResult:
        """
        Execute feature with hybrid loop pattern.

        Outer loop: Multi-session progression (SDK pattern)
        Inner loop: Same-session validation and self-healing (Ralph pattern)
        """
        feature_desc = feature['description']
        self.logger.info(f"\n{'='*60}")
        self.logger.info(f"🎯 Starting feature: {feature_desc}")
        self.logger.info(f"{'='*60}\n")

        # Get semantic hints if available
        semantic_hints = None
        if self.semantic_memory:
            try:
                feat_obj = Feature(
                    description=feature['description'],
                    tags=feature.get('tags', []),
                    risk_score=feature.get('risk_score', 0.5),
                    complexity=feature.get('complexity', 0.5)
                )
                similar = await self.semantic_memory.find_similar_features(feat_obj, limit=3)

                if similar:
                    semantic_hints = []
                    for sim in similar:
                        semantic_hints.append(
                            f"Similar feature (similarity: {sim.similarity:.0%}): {sim.approach}"
                        )
                    self.logger.info(f"💡 Found {len(similar)} similar features in memory")
            except Exception as e:
                self.logger.warning(f"⚠️  Could not retrieve semantic hints: {e}")

        # Outer loop: Multi-session (SDK pattern)
        for session_num in range(self.max_outer_sessions):
            self.logger.info(f"\n--- Session {session_num + 1}/{self.max_outer_sessions} ---")

            # Inner loop: Same-session self-healing (Ralph pattern)
            for attempt in range(self.max_inner_loops):
                self.logger.info(f"Attempt {attempt + 1}/{self.max_inner_loops} (session {session_num + 1})")

                # Execute session
                result = await self.execute_session_async(feature, session_num, semantic_hints)

                # Validate result
                validation = await self.validate_result(feature)

                # Save checkpoint
                self.create_checkpoint(feature, session_num, attempt, validation)

                if validation.success:
                    # Success! Save and return
                    self.logger.info(f"✅ Feature completed successfully!")
                    self.logger.info(f"   Quality score: {validation.quality_score:.0%}")
                    self.logger.info(f"   Sessions used: {session_num + 1}")
                    self.logger.info(f"   Attempts: {attempt + 1}")

                    # Store in semantic memory
                    if self.semantic_memory and result.success:
                        try:
                            feat_obj = Feature(
                                description=feature['description'],
                                tags=feature.get('tags', []),
                                risk_score=feature.get('risk_score', 0.5),
                                complexity=feature.get('complexity', 0.5)
                            )
                            solution = Solution(
                                approach=result.message[:200],
                                patterns=[],
                                outcome="success"
                            )
                            await self.semantic_memory.store_success(feat_obj, solution, result)
                            self.logger.info("💾 Stored success in semantic memory")
                        except Exception as e:
                            self.logger.warning(f"⚠️  Could not store in semantic memory: {e}")

                    self.clear_checkpoint()
                    return ExecutionResult(
                        success=True,
                        message=validation.message,
                        commit_hash=None,
                        model=self.model,
                        quality_score=validation.quality_score
                    )

                # Validation failed
                if validation.can_self_heal and attempt < self.max_inner_loops - 1:
                    # Ralph pattern: Same-session retry with reflection
                    self.logger.warning(f"⚠️  Validation failed, retrying in same session...")
                    reflection = await self.reflect_on_failure(feature, validation)
                    self.logger.debug(f"Reflection: {reflection[:200]}...")

                    # In a real implementation, we'd inject reflection into session context
                    # For Phase 1, we continue to next attempt
                    continue
                else:
                    # Can't self-heal or out of inner loops
                    self.logger.warning(f"⚠️  Cannot self-heal, breaking to outer loop")
                    break

            # Inner loop exhausted - try different approach in next session
            self.logger.info(f"📍 Session {session_num + 1} completed, preparing for next session...")

        # All attempts exhausted
        self.logger.error(f"❌ Feature failed after {self.max_outer_sessions} sessions")
        return ExecutionResult(
            success=False,
            message="Max sessions reached without success",
            commit_hash=None,
            model=self.model,
            quality_score=0.0
        )

    async def run(self):
        """Main execution loop - process all features."""
        features = self.load_feature_list()

        if not features:
            self.logger.error("❌ No features to process")
            return

        total_features = len(features)
        completed = sum(1 for f in features if f.get("passes", False))

        self.logger.info(f"\n{'='*60}")
        self.logger.info(f"🚀 SDK Bridge v2.0 Hybrid Loop Agent")
        self.logger.info(f"   Progress: {completed}/{total_features} features completed")
        self.logger.info(f"{'='*60}\n")

        while True:
            feature = self.get_next_feature(features)

            if not feature:
                self.logger.info("\n🎉 All features completed!")

                # Create completion signal
                completion_file = self.claude_dir / "sdk_complete.json"
                completion_file.parent.mkdir(exist_ok=True)
                with open(completion_file, 'w') as f:
                    json.dump({
                        "completed_at": datetime.utcnow().isoformat(),
                        "total_features": total_features,
                        "status": "success"
                    }, f, indent=2)

                break

            # Execute feature
            result = await self.execute_feature(feature)

            # Update feature list
            feature["passes"] = result.success
            self.save_feature_list(features)

            if not result.success:
                self.logger.error(f"❌ Feature stalled, moving to next")
                # In real implementation, might want to stop here or mark as blocking


def main():
    """CLI entry point."""
    import argparse

    parser = argparse.ArgumentParser(description="SDK Bridge v2.0 Hybrid Loop Agent")
    parser.add_argument("--project-dir", default=".", help="Project directory")
    parser.add_argument("--model", default="claude-sonnet-4-5-20250929", help="Claude model to use")
    parser.add_argument("--max-iterations", type=int, default=20, help="Max outer sessions")
    parser.add_argument("--max-inner-loops", type=int, default=5, help="Max same-session retries")
    parser.add_argument("--log-level", default="INFO", help="Log level")
    parser.add_argument("--disable-semantic-memory", action="store_true", help="Disable semantic memory")

    args = parser.parse_args()

    agent = HybridLoopAgent(
        project_dir=args.project_dir,
        model=args.model,
        max_inner_loops=args.max_inner_loops,
        max_outer_sessions=args.max_iterations,
        log_level=args.log_level,
        enable_semantic_memory=not args.disable_semantic_memory
    )

    asyncio.run(agent.run())


if __name__ == "__main__":
    main()
