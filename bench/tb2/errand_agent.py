"""`comide errand` as a Harbor agent, for Terminal-Bench 2.

    harbor run -p TB2 --agent-import-path errand_agent:Errand -m cf/@cf/zai-org/glm-5.3 ...

(with bench/tb2/ on PYTHONPATH; bench/tb2/measure.sh does all of it.)

The Linux binary bench/tb2/linux/build.sh made (COMIDE_ERRAND_BIN) is copied into the task's
container and run there, from the task's working directory: `comide errand INSTRUCTION`.
It is the binary alone: no golemide, no hew, one terminal as its tool. (comide_agent.py is
the other way: the whole bundle, run as `comide -p`.) It is not confined: the model's key is
in the container with it, which is why a measurement runs on a credentials file holding
nothing else.

The record of the run is written into /logs/agent as it goes (COMIDE_LOG_DIR):
trajectory.json with the tokens of every step, and cost.txt. Harbor mounts that directory
from this machine, so bench/tb2/cost.py can read what a run has cost while it is running.
"""

import os
import shlex
from pathlib import Path

from harbor.agents.installed.base import BaseInstalledAgent
from harbor.environments.base import BaseEnvironment
from harbor.models.agent.context import AgentContext

INSTALL_DIR = "/installed-agent/comide-errand"

# What comide reads its model's credentials from (almai, Cloudflare Workers AI).
CREDENTIALS = ("CLOUDFLARE_ACCOUNT_ID", "CLOUDFLARE_API_TOKEN")

# Settings of the errand's own that a measurement changes, passed into the task when set.
SETTINGS = ("COMIDE_MAX_TOKENS", "COMIDE_REASONING_BACK", "COMIDE_CHECK")


class Errand(BaseInstalledAgent):
    @staticmethod
    def name() -> str:
        return "comide-errand"

    def get_version_command(self) -> str | None:
        return f"{INSTALL_DIR}/comide --version"

    def parse_version(self, stdout: str) -> str:
        return stdout.strip().split()[-1] if stdout.strip() else ""

    async def install(self, environment: BaseEnvironment) -> None:
        binary = Path(os.environ.get("COMIDE_ERRAND_BIN", "")).expanduser()
        if not binary.is_file():
            raise RuntimeError(f"COMIDE_ERRAND_BIN is not a file: {binary}")
        await self.exec_as_root(environment, command=f"mkdir -p {INSTALL_DIR}")
        await environment.upload_file(binary, f"{INSTALL_DIR}/comide")
        await self.exec_as_root(
            environment,
            command=f"chmod a+rx {INSTALL_DIR} {INSTALL_DIR}/comide && {INSTALL_DIR}/comide --version",
        )

    def command(self, instruction: str) -> str:
        model = os.environ.get("COMIDE_ERRAND_MODEL", "cf:glm-5.3")
        args = f"errand {shlex.quote(instruction)} --model {shlex.quote(model)}"
        steps = os.environ.get("COMIDE_ERRAND_MAX_STEPS")
        if steps:
            args += f" --max-steps {int(steps)}"
        # comide's own exit is recorded, not returned: the verifier decides the task, and
        # a non-zero exit here would end the trial before it runs.
        return (
            f"COMIDE_LOG_DIR=/logs/agent {INSTALL_DIR}/comide {args}"
            " > /logs/agent/comide.txt 2> /logs/agent/comide.stderr.txt; "
            'echo "exit $?" > /logs/agent/exit.txt'
        )

    async def run(self, instruction: str, environment: BaseEnvironment, context: AgentContext) -> None:
        env = {k: os.environ[k] for k in CREDENTIALS + SETTINGS if os.environ.get(k)}
        await self.exec_as_agent(environment, command=self.command(self.render_instruction(instruction)), env=env)

    def populate_context_post_run(self, context: AgentContext) -> None:
        try:
            context.cost_usd = float((self.logs_dir / "cost.txt").read_text().strip().lstrip("$"))
        except (OSError, ValueError):
            pass
