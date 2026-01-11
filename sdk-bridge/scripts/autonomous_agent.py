#!/usr/bin/env python3
"""
Autonomous Agent Harness for long-running development tasks.
Uses the Claude Agent SDK to implement features from feature_list.json one by one.

Version 1.4.0 Features:
- Retry logic with exponential backoff
- Checkpoint-based crash recovery
- Structured logging with configurable levels
- Webhook notifications for completion/errors
- Feature priority ordering
"""

import os
import json
import argparse
import subprocess
import time
import sys
import asyncio
import logging
import urllib.request
import urllib.error
from datetime import datetime
from typing import Optional, Dict, Any, List

# Configure structured logging
def setup_logging(level: str = "INFO", log_file: Optional[str] = None) -> logging.Logger:
    """Set up structured logging with configurable levels."""
    logger = logging.getLogger("autonomous_agent")
    logger.setLevel(getattr(logging, level.upper(), logging.INFO))

    formatter = logging.Formatter(
        "[%(asctime)s] [%(levelname)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S"
    )

    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)

    if log_file:
        file_handler = logging.FileHandler(log_file, mode='a')
        file_handler.setFormatter(formatter)
        logger.addHandler(file_handler)

    return logger


def run_git(args: List[str], cwd: str, logger: logging.Logger) -> bool:
    """Execute git command with error handling."""
    try:
        subprocess.run(["git"] + args, cwd=cwd, check=True, capture_output=True)
        return True
    except subprocess.CalledProcessError as e:
        logger.error(f"Git error: {e.stderr.decode()}")
        return False


class WebhookNotifier:
    """Send webhook notifications for completion and error events."""

    def __init__(self, webhook_url: Optional[str], logger: logging.Logger):
        self.webhook_url = webhook_url
        self.logger = logger

    def notify(self, event: str, data: Dict[str, Any]) -> bool:
        """Send a webhook notification."""
        if not self.webhook_url:
            return True

        payload = {
            "event": event,
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "data": data
        }

        try:
            req = urllib.request.Request(
                self.webhook_url,
                data=json.dumps(payload).encode('utf-8'),
                headers={
                    'Content-Type': 'application/json',
                    'User-Agent': 'SDK-Bridge-Agent/1.4.0'
                },
                method='POST'
            )
            with urllib.request.urlopen(req, timeout=10) as response:
                self.logger.debug(f"Webhook sent: {event} -> {response.status}")
                return response.status == 200
        except urllib.error.URLError as e:
            self.logger.warning(f"Webhook failed: {e}")
            return False
        except Exception as e:
            self.logger.warning(f"Webhook error: {e}")
            return False

    def notify_completion(self, reason: str, features_completed: int, total_features: int):
        """Notify on agent completion."""
        self.notify("completion", {
            "reason": reason,
            "features_completed": features_completed,
            "total_features": total_features
        })

    def notify_error(self, error: str, feature: Optional[str] = None):
        """Notify on error."""
        self.notify("error", {
            "error": error,
            "feature": feature
        })

    def notify_feature_complete(self, feature: str, session: int):
        """Notify on feature completion."""
        self.notify("feature_complete", {
            "feature": feature,
            "session": session
        })


class CheckpointManager:
    """Manage checkpoint state for crash recovery."""

    def __init__(self, checkpoint_path: str, logger: logging.Logger):
        self.checkpoint_path = checkpoint_path
        self.logger = logger

    def save(self, state: Dict[str, Any]) -> bool:
        """Save checkpoint state to disk."""
        try:
            state["checkpoint_time"] = datetime.utcnow().isoformat() + "Z"
            temp_path = self.checkpoint_path + ".tmp"
            with open(temp_path, 'w') as f:
                json.dump(state, f, indent=2)
            os.rename(temp_path, self.checkpoint_path)
            self.logger.debug(f"Checkpoint saved: session={state.get('current_session')}")
            return True
        except Exception as e:
            self.logger.error(f"Failed to save checkpoint: {e}")
            return False

    def load(self) -> Optional[Dict[str, Any]]:
        """Load checkpoint state from disk."""
        if not os.path.exists(self.checkpoint_path):
            return None
        try:
            with open(self.checkpoint_path, 'r') as f:
                state = json.load(f)
            self.logger.info(f"Checkpoint loaded: session={state.get('current_session')}")
            return state
        except Exception as e:
            self.logger.warning(f"Failed to load checkpoint: {e}")
            return None

    def clear(self) -> bool:
        """Clear checkpoint after successful completion."""
        if os.path.exists(self.checkpoint_path):
            try:
                os.remove(self.checkpoint_path)
                self.logger.debug("Checkpoint cleared")
                return True
            except Exception as e:
                self.logger.warning(f"Failed to clear checkpoint: {e}")
                return False
        return True


class AutonomousAgent:
    """Main agent class for autonomous feature implementation."""

    # Retry configuration
    MAX_RETRIES = 3
    BACKOFF_BASE = 1  # seconds
    BACKOFF_MULTIPLIER = 2

    def __init__(
        self,
        project_dir: str,
        model: str,
        max_iterations: int,
        log_level: str = "INFO",
        webhook_url: Optional[str] = None
    ):
        self.project_dir = os.path.abspath(project_dir)
        self.model = model
        self.max_iterations = max_iterations

        # File paths
        self.feature_list_path = os.path.join(self.project_dir, "feature_list.json")
        self.progress_log_path = os.path.join(self.project_dir, "claude-progress.txt")
        self.protocol_path = os.path.join(self.project_dir, "CLAUDE.md")
        self.claude_dir = os.path.join(self.project_dir, ".claude")
        self.complete_signal_path = os.path.join(self.claude_dir, "sdk_complete.json")
        self.checkpoint_path = os.path.join(self.claude_dir, "sdk-checkpoint.json")

        os.makedirs(self.claude_dir, exist_ok=True)

        # Set up logging
        log_file = os.path.join(self.claude_dir, "sdk-bridge.log")
        self.logger = setup_logging(log_level, log_file)

        # Set up webhook notifier
        self.webhook = WebhookNotifier(webhook_url, self.logger)

        # Set up checkpoint manager
        self.checkpoint = CheckpointManager(self.checkpoint_path, self.logger)

        # Track session state
        self.current_session = 0
        self.features_completed = 0
        self.consecutive_failures = 0

    def load_features(self) -> Optional[List[Dict[str, Any]]]:
        """Load features from feature_list.json."""
        if not os.path.exists(self.feature_list_path):
            self.logger.error(f"Feature list not found: {self.feature_list_path}")
            return None
        try:
            with open(self.feature_list_path, 'r') as f:
                return json.load(f)
        except json.JSONDecodeError as e:
            self.logger.error(f"Invalid JSON in feature list: {e}")
            return None

    def save_features(self, features: List[Dict[str, Any]]) -> bool:
        """Save features to feature_list.json."""
        try:
            with open(self.feature_list_path, 'w') as f:
                json.dump(features, f, indent=2)
            return True
        except Exception as e:
            self.logger.error(f"Failed to save features: {e}")
            return False

    def log_progress(self, message: str):
        """Append message to progress log."""
        try:
            with open(self.progress_log_path, 'a') as f:
                f.write(f"\n[{datetime.now().isoformat()}] {message}\n")
        except Exception as e:
            self.logger.warning(f"Failed to log progress: {e}")

    def get_next_feature(self, features: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
        """Get the next feature to implement, respecting priority ordering."""
        pending = [f for f in features if not f.get("passes", False)]
        if not pending:
            return None

        # Sort by priority (higher priority first), then by original order
        # Default priority is 0 if not specified
        pending_with_index = [(i, f) for i, f in enumerate(features) if not f.get("passes", False)]
        pending_with_index.sort(key=lambda x: (-x[1].get("priority", 0), x[0]))

        if pending_with_index:
            return pending_with_index[0][1]
        return None

    def count_completed(self, features: List[Dict[str, Any]]) -> int:
        """Count completed features."""
        return sum(1 for f in features if f.get("passes", False))

    def restore_from_checkpoint(self) -> bool:
        """Attempt to restore state from checkpoint after a crash."""
        checkpoint = self.checkpoint.load()
        if checkpoint:
            self.current_session = checkpoint.get("current_session", 0)
            self.features_completed = checkpoint.get("features_completed", 0)
            self.consecutive_failures = checkpoint.get("consecutive_failures", 0)
            self.logger.info(
                f"Restored from checkpoint: session={self.current_session}, "
                f"completed={self.features_completed}"
            )
            return True
        return False

    def save_checkpoint(self, current_feature: Optional[str] = None):
        """Save current state to checkpoint file."""
        state = {
            "current_session": self.current_session,
            "features_completed": self.features_completed,
            "consecutive_failures": self.consecutive_failures,
            "current_feature": current_feature,
            "project_dir": self.project_dir,
            "model": self.model,
            "max_iterations": self.max_iterations
        }
        self.checkpoint.save(state)

    def run(self):
        """Main execution loop."""
        self.logger.info(f"Starting autonomous agent in {self.project_dir}")
        self.logger.info(f"Model: {self.model}, Max iterations: {self.max_iterations}")

        # Try to restore from checkpoint
        restored = self.restore_from_checkpoint()
        if restored:
            self.logger.info("Resuming from previous checkpoint")

        start_session = self.current_session

        for i in range(start_session, self.max_iterations):
            self.current_session = i + 1
            self.logger.info(f"--- Session {self.current_session}/{self.max_iterations} ---")

            features = self.load_features()
            if features is None:
                self.webhook.notify_error("Failed to load features")
                break

            feature = self.get_next_feature(features)
            if not feature:
                self.logger.info("All features completed!")
                self.signal_completion("success", features)
                return

            feature_desc = feature.get('description', 'Unknown feature')
            priority = feature.get('priority', 0)
            self.logger.info(f"Starting work on feature (priority={priority}): {feature_desc}")

            # Save checkpoint before starting
            self.save_checkpoint(feature_desc)

            success = self.execute_session_with_retry(feature)

            if success:
                self.logger.info(f"Feature completed successfully: {feature_desc}")
                feature["passes"] = True
                self.save_features(features)
                self.log_progress(f"Completed: {feature_desc}")
                self.features_completed += 1
                self.consecutive_failures = 0

                run_git(["add", "."], self.project_dir, self.logger)
                run_git(
                    ["commit", "-m", f"SDK: completed feature - {feature_desc}"],
                    self.project_dir,
                    self.logger
                )

                # Notify webhook of feature completion
                self.webhook.notify_feature_complete(feature_desc, self.current_session)
            else:
                self.logger.warning(f"Feature failed: {feature_desc}")
                self.log_progress(f"Failed: {feature_desc}")
                self.consecutive_failures += 1

                # Check stall threshold (3 consecutive failures)
                if self.consecutive_failures >= 3:
                    self.logger.error("Stall detected: 3 consecutive failures")
                    self.webhook.notify_error("Stall detected", feature_desc)
                    self.signal_completion("stall_detected", features)
                    return

            # Save checkpoint after each session
            self.save_checkpoint()

            # Small cooldown between sessions
            time.sleep(2)

        self.logger.info("Reached maximum iterations.")
        features = self.load_features()
        self.signal_completion("max_iterations_reached", features)

    def execute_session_with_retry(self, feature: Dict[str, Any]) -> bool:
        """Execute session with exponential backoff retry logic."""
        for attempt in range(self.MAX_RETRIES):
            if attempt > 0:
                delay = self.BACKOFF_BASE * (self.BACKOFF_MULTIPLIER ** (attempt - 1))
                self.logger.info(f"Retry attempt {attempt + 1}/{self.MAX_RETRIES} after {delay}s delay")
                time.sleep(delay)

            try:
                success = self.execute_session(feature)
                if success:
                    return True
                # If session returned False (feature not completed), don't retry
                # Only retry on exceptions/errors
                self.logger.debug(f"Session returned failure for feature")
                return False
            except Exception as e:
                self.logger.warning(f"Session attempt {attempt + 1} failed with error: {e}")
                if attempt == self.MAX_RETRIES - 1:
                    self.logger.error(f"All {self.MAX_RETRIES} retry attempts exhausted")
                    self.webhook.notify_error(str(e), feature.get('description'))
                    return False

        return False

    def execute_session(self, feature: Dict[str, Any]) -> bool:
        """Execute a single session for implementing a feature."""
        return asyncio.run(self._execute_session_async(feature))

    async def _execute_session_async(self, feature: Dict[str, Any]) -> bool:
        """Async implementation of session execution."""
        try:
            from claude_agent_sdk import query, ClaudeAgentOptions

            # Read protocol
            protocol = ""
            if os.path.exists(self.protocol_path):
                with open(self.protocol_path, 'r') as f:
                    protocol = f.read()

            # Check for API authentication
            oauth_token = os.environ.get("CLAUDE_CODE_OAUTH_TOKEN")
            api_key = os.environ.get("ANTHROPIC_API_KEY")

            if not oauth_token and not api_key:
                self.logger.error("No API key found. Set CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY")
                raise RuntimeError("Missing API authentication")

            auth_method = 'CLAUDE_CODE_OAUTH_TOKEN' if oauth_token else 'ANTHROPIC_API_KEY'
            self.logger.debug(f"Using auth: {auth_method}")

            prompt = f"""
I am working on a project in {self.project_dir}.
The project protocol is defined in CLAUDE.md:
{protocol}

My current task is to implement the following feature:
Description: {feature['description']}
Test Criteria: {feature.get('test', 'None provided')}
Priority: {feature.get('priority', 0)}

Please implement this feature, ensure it passes its tests, and let me know when you are done.
Include a brief summary of what you did. Say SUCCESS if you completed it successfully.
"""
            options = ClaudeAgentOptions(
                model=self.model,
                max_turns=50,
            )

            result_text = ""
            async for message in query(prompt=prompt, options=options):
                if hasattr(message, 'content'):
                    for block in message.content:
                        if hasattr(block, 'text'):
                            result_text += block.text
                            # Log truncated response
                            text_preview = block.text[:100].replace('\n', ' ')
                            self.logger.debug(f"Agent: {text_preview}...")

            # Analyze result to determine success
            success = "SUCCESS" in result_text.upper() or "COMPLETED" in result_text.upper()
            return success

        except ImportError as e:
            self.logger.error(f"claude-agent-sdk import failed: {e}")
            raise RuntimeError(f"SDK import failed: {e}")
        except Exception as e:
            self.logger.error(f"Error during agent execution: {str(e)}")
            raise

    def signal_completion(self, reason: str, features: Optional[List[Dict[str, Any]]] = None):
        """Signal that the agent has completed its run."""
        completed = self.count_completed(features) if features else self.features_completed
        total = len(features) if features else 0

        data = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "reason": reason,
            "project_dir": self.project_dir,
            "session_count": self.current_session,
            "features_completed": completed,
            "total_features": total
        }

        try:
            with open(self.complete_signal_path, 'w') as f:
                json.dump(data, f, indent=2)
            self.logger.info(f"Completion signal written: {reason}")
        except Exception as e:
            self.logger.error(f"Failed to write completion signal: {e}")

        # Clear checkpoint on successful completion
        self.checkpoint.clear()

        # Send webhook notification
        self.webhook.notify_completion(reason, completed, total)


def parse_config_file(project_dir: str) -> Dict[str, Any]:
    """Parse sdk-bridge.local.md for configuration values."""
    config_path = os.path.join(project_dir, ".claude", "sdk-bridge.local.md")
    config = {}

    if not os.path.exists(config_path):
        return config

    try:
        with open(config_path, 'r') as f:
            content = f.read()

        # Extract YAML frontmatter
        if content.startswith('---'):
            parts = content.split('---', 2)
            if len(parts) >= 3:
                frontmatter = parts[1]
                for line in frontmatter.strip().split('\n'):
                    if ':' in line:
                        key, value = line.split(':', 1)
                        key = key.strip()
                        value = value.strip()
                        # Parse boolean values
                        if value.lower() == 'true':
                            config[key] = True
                        elif value.lower() == 'false':
                            config[key] = False
                        # Parse numeric values
                        elif value.isdigit():
                            config[key] = int(value)
                        else:
                            config[key] = value
    except Exception:
        pass

    return config


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Autonomous Agent Harness for long-running development tasks"
    )
    parser.add_argument("--project-dir", required=True, help="Project directory path")
    parser.add_argument("--model", default="claude-sonnet-4-5-20250929", help="Claude model to use")
    parser.add_argument("--max-iterations", type=int, default=10, help="Maximum sessions to run")
    parser.add_argument("--log-level", default="INFO",
                       choices=["DEBUG", "INFO", "WARNING", "ERROR"],
                       help="Logging level")
    parser.add_argument("--webhook-url", default=None, help="Webhook URL for notifications")
    args = parser.parse_args()

    # Try to load additional config from sdk-bridge.local.md
    config = parse_config_file(args.project_dir)

    # Command-line args override config file
    webhook_url = args.webhook_url or config.get("webhook_url")
    log_level = args.log_level if args.log_level != "INFO" else config.get("log_level", "INFO")

    agent = AutonomousAgent(
        project_dir=args.project_dir,
        model=args.model,
        max_iterations=args.max_iterations,
        log_level=log_level,
        webhook_url=webhook_url
    )
    agent.run()
