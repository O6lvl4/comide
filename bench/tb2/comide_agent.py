"""comide as a Harbor agent, for Terminal-Bench 2.0.

    harbor run -p ~/workspace/github.com/harbor-framework/terminal-bench-2 \\
      --agent-import-path comide_agent:Comide -m cf/glm-5.3 ...

(with bench/tb2 on PYTHONPATH; bench/tb2/run.sh does all of it.)

The Linux bundle bench/tb2/build-bundle.sh made (COMIDE_TB2_BUNDLE) is copied into the
task container, and comide runs there headless (`comide -p INSTRUCTION --yes`) from the
task's working directory. It runs inside porta unless COMIDE_TB2_CONFINE=none:

    app      all of comide inside one porta run: writes only to the working directory
             and /tmp; network open, because the tasks are allowed the internet;
             credentials passed by name
    onogoro  comide outside, each tool call confined by porta through onogoro: no key
             reaches a command, golemide gets the model keys by name, and porta's
             refusals come back to the model. Commands may also write /usr, /var, /etc
             and /opt (ONOGORO_WRITABLE): the container is thrown away after the task,
             and its tasks expect pip and apt to install into the system
    none     comide runs as it is

Terminal-Bench containers run as root, so porta is given --allow-root. The model is
comide's own spec (`cf:glm-5.3-flash`, `anthropic:…`, …): Harbor's `-m provider/model`
is turned into it by putting a colon where the first slash is.
"""

import os
import shlex
from pathlib import Path

from harbor.agents.installed.base import BaseInstalledAgent
from harbor.environments.base import BaseEnvironment
from harbor.models.agent.context import AgentContext

INSTALL_DIR = "/installed-agent/comide"

# What comide and golemide read their models' credentials from.
CREDENTIALS = (
    "CLOUDFLARE_ACCOUNT_ID",
    "CLOUDFLARE_API_TOKEN",
    "ANTHROPIC_API_KEY",
    "GEMINI_API_KEY",
    "GOOGLE_API_KEY",
    "OPENAI_API_KEY",
    "OPENROUTER_API_KEY",
    # claude_bridge.py: the Claude subscription `claude` is logged in with, on the host.
    "CLAUDECLI_BASE_URL",
    "CLAUDECLI_API_KEY",
)


class Comide(BaseInstalledAgent):
    @staticmethod
    def name() -> str:
        return "comide"

    def get_version_command(self) -> str | None:
        return f"cat {INSTALL_DIR}/SOURCES"

    def parse_version(self, stdout: str) -> str:
        for line in stdout.splitlines():
            if line.startswith("comide "):
                return line.split()[1]
        return stdout.strip()

    async def install(self, environment: BaseEnvironment) -> None:
        bundle = Path(os.environ.get("COMIDE_TB2_BUNDLE", "")).expanduser()
        if not (bundle / "bin" / "comide").is_file():
            raise RuntimeError(f"COMIDE_TB2_BUNDLE has no bin/comide: {bundle}")
        await environment.upload_dir(bundle, INSTALL_DIR)
        await self.exec_as_root(
            environment,
            command=f"chmod -R a+rX {INSTALL_DIR} && chmod a+x {INSTALL_DIR}/bin/* && {INSTALL_DIR}/bin/comide --help > /dev/null",
        )

    def comide_model(self) -> str:
        m = self.model_name or os.environ.get("COMIDE_TB2_MODEL", "cf/glm-5.3")
        return m.replace("/", ":", 1) if ":" not in m else m

    def command(self, instruction: str) -> str:
        confine = os.environ.get("COMIDE_TB2_CONFINE", "app")
        args = f"-p {shlex.quote(instruction)} --yes --model {shlex.quote(self.comide_model())}"
        steps = os.environ.get("COMIDE_TB2_MAX_STEPS")
        if steps:
            args += f" --max-steps {int(steps)}"
        if confine == "none":
            run = f"{INSTALL_DIR}/bin/comide {args}"
        elif confine == "onogoro":
            run = (
                f"ONOGORO_COMIDE={INSTALL_DIR}/bin/comide ONOGORO_PORTA={INSTALL_DIR}/bin/porta"
                f" ONOGORO_WRITABLE=/usr:/var:/etc:/opt {INSTALL_DIR}/bin/onogoro {args}"
            )
        else:
            # `porta run CMD [porta's flags] -- [CMD's arguments]`. In a Docker container
            # porta has no user namespace and confines by Landlock alone; it says so on
            # stderr, and the confinement of writes and credential reads still holds.
            # $HOME is not granted: it is /root here, and where a task image has a
            # /root/.ssh, Landlock cannot keep it closed inside a grant of /root, so porta
            # refuses the run (break-filter-js-from-html).
            passed = ",".join(CREDENTIALS + ("COMIDE_COST_FILE", "TERM", "LANG"))
            run = (
                f"{INSTALL_DIR}/bin/porta run {INSTALL_DIR}/bin/comide --allow-root"
                ' -v "$PWD" -v /tmp'
                f" --env-pass {passed}"
                f" -- {args}"
            )
        # golemide, hew, ctxgate and gramide are found on PATH, next to comide. The cost
        # goes to /tmp and is copied to /logs/agent after the run: on Docker Desktop,
        # /logs/agent is a host-shared mount that Landlock will not let porta write
        # (almide/porta#36). It is also copied every 20 s while comide runs, because a run
        # that reaches the task's timeout is killed before the copy after it.
        return (
            f'export PATH="{INSTALL_DIR}/bin:$PATH" COMIDE_COST_FILE=/tmp/comide-cost.txt; '
            "( while sleep 20; do cp /tmp/comide-cost.txt /logs/agent/cost.txt 2>/dev/null; done ) & "
            f"{run} > /logs/agent/comide.txt 2> /logs/agent/comide.stderr.txt; "
            # comide's own exit is recorded, not returned: the verifier decides the task,
            # and a non-zero exit here would end the trial before it runs.
            'code=$?; kill %1 2>/dev/null; cp /tmp/comide-cost.txt /logs/agent/cost.txt 2>/dev/null; echo "exit $code" > /logs/agent/exit.txt'
        )

    async def run(self, instruction: str, environment: BaseEnvironment, context: AgentContext) -> None:
        env = {k: os.environ[k] for k in CREDENTIALS if os.environ.get(k)}
        await self.exec_as_agent(environment, command=self.command(self.render_instruction(instruction)), env=env)

    def populate_context_post_run(self, context: AgentContext) -> None:
        cost = self.logs_dir / "cost.txt"
        try:
            text = cost.read_text().strip().lstrip("$")
            context.cost_usd = float(text)
        except (OSError, ValueError):
            pass
