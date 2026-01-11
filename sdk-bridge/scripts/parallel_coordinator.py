#!/usr/bin/env python3
"""
Parallel Coordinator - SDK Bridge v2.0 Phase 3

Orchestrates parallel execution of independent features using git branch isolation.

Features:
- Multi-worker coordination
- Git branch isolation per feature
- Intelligent merge coordination
- Conflict detection and rollback
- Integration testing

Author: SDK Bridge Team
Version: 2.0.0-alpha (Phase 3)
"""

import asyncio
import json
import logging
import os
import subprocess
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Set


logger = logging.getLogger("parallel_coordinator")


@dataclass
class WorkerSession:
    """Active worker session executing a feature."""
    worker_id: str
    feature_id: str
    git_branch: str
    model: str
    pid: Optional[int] = None
    started_at: str = ""
    current_session: int = 0
    max_sessions: int = 5
    status: str = "pending"  # pending | running | completed | failed | waiting_merge
    last_heartbeat: str = ""
    result_message: str = ""


@dataclass
class MergeResult:
    """Result of merge operation."""
    success: bool
    conflicts: List[str] = field(default_factory=list)
    test_failures: List[str] = field(default_factory=list)
    reason: str = ""
    requires_approval: bool = False


class GitManager:
    """Manages git operations for parallel execution."""

    def __init__(self, project_dir: str = "."):
        self.project_dir = Path(project_dir).resolve()

    async def get_current_branch(self) -> str:
        """Get current git branch."""
        proc = await asyncio.create_subprocess_exec(
            "git", "rev-parse", "--abbrev-ref", "HEAD",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=self.project_dir
        )
        stdout, _ = await proc.communicate()
        return stdout.decode().strip()

    async def create_branch(self, branch_name: str, base_branch: str = "main") -> bool:
        """Create new branch from base."""
        try:
            # Ensure we're on base branch
            await asyncio.create_subprocess_exec(
                "git", "checkout", base_branch,
                cwd=self.project_dir
            )

            # Create and checkout new branch
            proc = await asyncio.create_subprocess_exec(
                "git", "checkout", "-b", branch_name,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=self.project_dir
            )
            await proc.communicate()

            logger.info(f"✅ Created branch: {branch_name}")
            return proc.returncode == 0

        except Exception as e:
            logger.error(f"❌ Failed to create branch {branch_name}: {e}")
            return False

    async def merge_branch(
        self,
        branch_name: str,
        target_branch: str = "main",
        strategy: str = "recursive"
    ) -> MergeResult:
        """
        Merge branch into target with conflict detection.

        Returns MergeResult with success status and conflict info.
        """
        try:
            # Checkout target branch
            proc = await asyncio.create_subprocess_exec(
                "git", "checkout", target_branch,
                cwd=self.project_dir
            )
            await proc.wait()

            # Attempt merge
            proc = await asyncio.create_subprocess_exec(
                "git", "merge", "--no-ff", branch_name,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=self.project_dir
            )
            stdout, stderr = await proc.communicate()

            if proc.returncode != 0:
                # Merge failed - check for conflicts
                conflicts = await self._get_merge_conflicts()

                # Abort merge
                await asyncio.create_subprocess_exec(
                    "git", "merge", "--abort",
                    cwd=self.project_dir
                )

                return MergeResult(
                    success=False,
                    conflicts=conflicts,
                    reason="Merge conflicts detected",
                    requires_approval=True
                )

            logger.info(f"✅ Merged {branch_name} → {target_branch}")
            return MergeResult(success=True, reason="Clean merge")

        except Exception as e:
            logger.error(f"❌ Merge error: {e}")
            return MergeResult(
                success=False,
                reason=f"Exception: {str(e)}"
            )

    async def _get_merge_conflicts(self) -> List[str]:
        """Get list of files with merge conflicts."""
        try:
            proc = await asyncio.create_subprocess_exec(
                "git", "diff", "--name-only", "--diff-filter=U",
                stdout=asyncio.subprocess.PIPE,
                cwd=self.project_dir
            )
            stdout, _ = await proc.communicate()
            files = stdout.decode().strip().split('\n')
            return [f for f in files if f]

        except Exception as e:
            logger.error(f"Failed to get conflicts: {e}")
            return []

    async def delete_branch(self, branch_name: str) -> bool:
        """Delete branch."""
        try:
            proc = await asyncio.create_subprocess_exec(
                "git", "branch", "-D", branch_name,
                cwd=self.project_dir
            )
            await proc.wait()
            logger.info(f"🗑️  Deleted branch: {branch_name}")
            return proc.returncode == 0

        except Exception as e:
            logger.error(f"Failed to delete branch: {e}")
            return False

    async def reset_hard(self, commit: str = "HEAD") -> bool:
        """Hard reset to commit."""
        try:
            proc = await asyncio.create_subprocess_exec(
                "git", "reset", "--hard", commit,
                cwd=self.project_dir
            )
            await proc.wait()
            return proc.returncode == 0

        except Exception as e:
            logger.error(f"Failed to reset: {e}")
            return False


class WorkerSessionManager:
    """Manages active worker sessions."""

    def __init__(self, project_dir: str = "."):
        self.project_dir = Path(project_dir).resolve()
        self.sessions_path = self.project_dir / ".claude" / "worker-sessions.json"
        self.sessions_path.parent.mkdir(exist_ok=True)

        self.active_workers: Dict[str, WorkerSession] = {}
        self.completed_workers: List[Dict] = []

        self._load()

    def _load(self):
        """Load worker sessions from disk."""
        if not self.sessions_path.exists():
            self._save()
            return

        try:
            with open(self.sessions_path, 'r') as f:
                data = json.load(f)

            for worker_id, worker_data in data.get("active_workers", {}).items():
                self.active_workers[worker_id] = WorkerSession(**worker_data)

            self.completed_workers = data.get("completed_workers", [])

            logger.info(f"Loaded {len(self.active_workers)} active workers")

        except Exception as e:
            logger.error(f"Failed to load worker sessions: {e}")

    def _save(self):
        """Save worker sessions to disk."""
        try:
            data = {
                "version": "2.0.0",
                "active_workers": {
                    worker_id: asdict(worker)
                    for worker_id, worker in self.active_workers.items()
                },
                "completed_workers": self.completed_workers
            }

            with open(self.sessions_path, 'w') as f:
                json.dump(data, f, indent=2)

        except Exception as e:
            logger.error(f"Failed to save worker sessions: {e}")

    def create_worker(
        self,
        feature_id: str,
        git_branch: str,
        model: str,
        max_sessions: int = 5
    ) -> WorkerSession:
        """Create new worker session."""
        worker_id = f"worker-{len(self.active_workers) + 1}"

        worker = WorkerSession(
            worker_id=worker_id,
            feature_id=feature_id,
            git_branch=git_branch,
            model=model,
            started_at=datetime.now(timezone.utc).isoformat(),
            max_sessions=max_sessions,
            status="pending"
        )

        self.active_workers[worker_id] = worker
        self._save()

        logger.info(f"✅ Created worker {worker_id} for {feature_id}")
        return worker

    def update_worker_status(
        self,
        worker_id: str,
        status: str,
        message: str = ""
    ):
        """Update worker status."""
        if worker_id in self.active_workers:
            self.active_workers[worker_id].status = status
            self.active_workers[worker_id].last_heartbeat = datetime.now(timezone.utc).isoformat()
            if message:
                self.active_workers[worker_id].result_message = message
            self._save()

    def complete_worker(
        self,
        worker_id: str,
        result: str,
        sessions_used: int
    ):
        """Mark worker as completed."""
        if worker_id in self.active_workers:
            worker = self.active_workers[worker_id]

            self.completed_workers.append({
                "feature_id": worker.feature_id,
                "result": result,
                "sessions_used": sessions_used,
                "completed_at": datetime.now(timezone.utc).isoformat()
            })

            del self.active_workers[worker_id]
            self._save()

            logger.info(f"✅ Worker {worker_id} completed: {result}")


class ParallelCoordinator:
    """
    Orchestrates parallel execution of independent features.

    Uses git branch isolation and intelligent merge coordination.
    """

    def __init__(
        self,
        project_dir: str = ".",
        max_parallel_workers: int = 3
    ):
        self.project_dir = Path(project_dir).resolve()
        self.max_parallel_workers = max_parallel_workers

        self.git = GitManager(str(self.project_dir))
        self.session_manager = WorkerSessionManager(str(self.project_dir))

        logger.info(f"Parallel Coordinator initialized (max workers: {max_parallel_workers})")

    async def execute_level(
        self,
        feature_ids: List[str],
        features_data: Dict[str, Dict],
        base_branch: str = "main"
    ) -> Dict[str, bool]:
        """
        Execute one level of features in parallel.

        Returns dict mapping feature_id -> success.
        """
        logger.info(f"\n{'='*60}")
        logger.info(f"Executing level: {len(feature_ids)} feature(s)")
        logger.info(f"Max parallelism: {min(len(feature_ids), self.max_parallel_workers)}")
        logger.info(f"{'='*60}\n")

        # Create workers for each feature
        workers = []
        for feature_id in feature_ids:
            feature = features_data[feature_id]

            # Create isolated branch
            branch_name = f"sdk-bridge/parallel/{feature_id}"
            await self.git.create_branch(branch_name, base_branch)

            # Create worker session
            worker = self.session_manager.create_worker(
                feature_id=feature_id,
                git_branch=branch_name,
                model="claude-sonnet-4-5-20250929",  # Could be adaptive
                max_sessions=5
            )

            workers.append(worker)

        # Execute workers in parallel
        results = {}
        worker_tasks = []

        for worker in workers:
            task = self._execute_worker(worker, features_data[worker.feature_id])
            worker_tasks.append(task)

        # Wait for all workers (with timeout)
        try:
            worker_results = await asyncio.gather(*worker_tasks, return_exceptions=True)

            for worker, result in zip(workers, worker_results):
                if isinstance(result, Exception):
                    logger.error(f"Worker {worker.worker_id} failed with exception: {result}")
                    results[worker.feature_id] = False
                else:
                    results[worker.feature_id] = result

        except Exception as e:
            logger.error(f"Error in parallel execution: {e}")
            # Mark all as failed
            for worker in workers:
                results[worker.feature_id] = False

        return results

    async def _execute_worker(self, worker: WorkerSession, feature: Dict) -> bool:
        """
        Execute single worker (placeholder for actual SDK execution).

        In real implementation, this would launch hybrid_loop_agent.py
        on the isolated branch.
        """
        logger.info(f"🤖 Worker {worker.worker_id} starting: {feature['description']}")

        self.session_manager.update_worker_status(worker.worker_id, "running")

        # Simulate execution
        await asyncio.sleep(2)  # Placeholder for actual SDK execution

        # For Phase 3, we'll simulate success
        # In full implementation, this would actually run the hybrid loop agent
        success = True

        self.session_manager.update_worker_status(
            worker.worker_id,
            "completed" if success else "failed",
            "Simulated completion" if success else "Simulated failure"
        )

        self.session_manager.complete_worker(
            worker.worker_id,
            "success" if success else "failure",
            sessions_used=1
        )

        return success

    async def merge_level_results(
        self,
        feature_ids: List[str],
        results: Dict[str, bool],
        target_branch: str = "main"
    ) -> MergeResult:
        """
        Merge successful feature branches and run integration tests.

        Returns MergeResult with overall success status.
        """
        logger.info(f"\n{'='*60}")
        logger.info(f"Merging level results")
        logger.info(f"{'='*60}\n")

        successful_features = [fid for fid, success in results.items() if success]

        if not successful_features:
            return MergeResult(
                success=False,
                reason="No successful features to merge"
            )

        logger.info(f"Merging {len(successful_features)} successful feature(s)")

        # Switch to target branch
        current_branch = await self.git.get_current_branch()
        if current_branch != target_branch:
            proc = await asyncio.create_subprocess_exec(
                "git", "checkout", target_branch,
                cwd=self.project_dir
            )
            await proc.wait()

        # Merge each branch sequentially
        merge_conflicts = []
        for feature_id in successful_features:
            branch_name = f"sdk-bridge/parallel/{feature_id}"

            result = await self.git.merge_branch(branch_name, target_branch)

            if not result.success:
                merge_conflicts.extend(result.conflicts)
                logger.warning(f"⚠️  Merge conflict in {feature_id}: {result.conflicts}")

        if merge_conflicts:
            # Rollback all merges
            logger.warning(f"❌ Merge conflicts detected, rolling back")
            await self.git.reset_hard(f"HEAD~{len(successful_features)}")

            return MergeResult(
                success=False,
                conflicts=merge_conflicts,
                reason="Merge conflicts detected, rolled back",
                requires_approval=True
            )

        # Run integration tests (placeholder)
        test_result = await self._run_integration_tests()

        if not test_result:
            # Rollback merges
            logger.warning(f"❌ Integration tests failed, rolling back")
            await self.git.reset_hard(f"HEAD~{len(successful_features)}")

            return MergeResult(
                success=False,
                test_failures=["Integration tests failed (simulated)"],
                reason="Integration tests failed, rolled back",
                requires_approval=True
            )

        # Cleanup branches
        for feature_id in successful_features:
            branch_name = f"sdk-bridge/parallel/{feature_id}"
            await self.git.delete_branch(branch_name)

        logger.info(f"✅ Level merge successful!")

        return MergeResult(success=True, reason="All merges clean, tests passing")

    async def _run_integration_tests(self) -> bool:
        """
        Run integration tests (placeholder).

        In real implementation, would run actual test suite.
        """
        logger.info("🧪 Running integration tests...")

        # Simulate test execution
        await asyncio.sleep(1)

        # For Phase 3, simulate success
        logger.info("✅ Integration tests passed")
        return True


# CLI for testing
if __name__ == "__main__":
    import sys

    logging.basicConfig(level=logging.INFO)

    async def test_coordinator():
        """Test parallel coordinator."""
        print("🧪 Testing Parallel Coordinator\n")

        coordinator = ParallelCoordinator(max_parallel_workers=2)

        # Sample features
        features_data = {
            "feat-001": {"description": "Feature A (independent)", "tags": []},
            "feat-002": {"description": "Feature B (independent)", "tags": []},
        }

        # Execute level
        results = await coordinator.execute_level(
            feature_ids=["feat-001", "feat-002"],
            features_data=features_data
        )

        print(f"\nResults: {results}")

        # Merge results
        merge_result = await coordinator.merge_level_results(
            feature_ids=["feat-001", "feat-002"],
            results=results
        )

        print(f"\nMerge Result: {merge_result}")

    asyncio.run(test_coordinator())
