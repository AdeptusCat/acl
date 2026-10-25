"""Run stress regressions with isolated user data and fail on Godot script errors."""
from __future__ import annotations

import argparse
import csv
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCENES = (
    "squad_attention_regression",
    "attention_stress_regression",
    "passive_overload_regression",
    "stress_balance_regression",
    "stress_recovery_regression",
    "stress_inputs_regression",
    "stress_resilience_regression",
    "command_connections_regression",
    "target_hit_chance_regression",
    "stress_scenarios_regression",
    "squad_fire_exchange_regression",
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot", help="Godot 4.7 executable")
    parser.add_argument("--output", type=Path, default=Path("/tmp/acl-stress-results"))
    parser.add_argument("--strict-balance", action="store_true",
                        help="Fail whole-squad exchanges on provisional balance alerts")
    args = parser.parse_args()
    executable = shutil.which(args.godot)
    if executable is None:
        parser.error(f"Godot executable not found: {args.godot}")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    failed = []
    with tempfile.TemporaryDirectory(prefix="acl-stress-") as temporary:
        environment = os.environ.copy()
        for variable, directory in (
            ("XDG_DATA_HOME", "data"),
            ("XDG_CONFIG_HOME", "config"),
            ("XDG_CACHE_HOME", "cache"),
        ):
            environment[variable] = str(Path(temporary) / directory)
        for scene in SCENES:
            frame_rate = "120"
            timeout = 120
            if scene == "squad_fire_exchange_regression":
                frame_rate = "60"
                timeout = 600
            command = [executable, "--headless", "--path", str(ROOT), "--fixed-fps", frame_rate,
                       f"res://tests/{scene}.tscn"]
            if scene == "stress_scenarios_regression":
                command += ["--", f"--report={output / 'stress_scenarios.csv'}"]
            if scene == "squad_fire_exchange_regression":
                command += ["--", f"--output={output}"]
                if args.strict_balance:
                    command += ["--strict-balance"]
            try:
                result = subprocess.run(command, cwd=ROOT, env=environment,
                                        capture_output=True, text=True, timeout=timeout)
                log = result.stdout + result.stderr
                success = result.returncode == 0 and not any(
                    marker in log for marker in ("SCRIPT ERROR:", "ERROR:")
                )
                # Godot can return zero after a script aborts; require completion too.
                success = success and "failures: 0" in log.lower()
            except subprocess.TimeoutExpired as error:
                log = f"Timed out after {error.timeout} seconds\n"
                for fragment in (error.stdout, error.stderr):
                    if isinstance(fragment, bytes):
                        log += fragment.decode(errors="replace")
                    elif fragment:
                        log += fragment
                success = False
            (output / f"{scene}.log").write_text(log)
            print(f"{'PASS' if success else 'FAIL'} {scene}", flush=True)
            if scene == "squad_fire_exchange_regression":
                for line in log.splitlines():
                    if line.startswith("Whole-squad balance alerts:"):
                        print(line, flush=True)
                print(f"Whole-squad report: {output / 'squad_fire_exchange.csv'}", flush=True)
            if not success:
                failed.append(scene)
                print(log[-6000:], file=sys.stderr)
    report = output / "stress_scenarios.csv"
    if not failed and report.exists():
        with report.open(newline="") as source:
            rows = list(csv.DictReader(source))
        sustained = [row for row in rows if row["phase"] == "sustained"]
        print(f"Report: {report} ({len(rows)} cases, {len(sustained)} sustained)")
        for weapon in sorted({row["weapon"] for row in sustained}):
            baseline = next(row for row in sustained if row["weapon"] == weapon
                            and row["profile"] == "unsupported" and row["cover"] == "2"
                            and row["directions"] == "2")
            supported = next(row for row in sustained if row["weapon"] == weapon
                             and row["profile"] == "nearby_hq" and row["cover"] == "2"
                             and row["directions"] == "2")
            print(f"{weapon}: stress at 30s, cover 2, opposing fire: "
                  f"{float(baseline['stress_at_30s']):.2f}; nearby HQ: "
                  f"{float(supported['stress_at_30s']):.2f}")
    print(f"Stress suites: {len(SCENES)}; failed: {len(failed)}")
    return int(bool(failed))


if __name__ == "__main__":
    sys.exit(main())
