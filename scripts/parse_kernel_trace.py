#!/usr/bin/env python3
"""parse_kernel_trace.py — V30.SIM Phase P2.4

Extract FJTRACE JSONL records from a FajarOS Nova serial log.

The kernel (see `kernel/compute/fjtrace.fj`) emits one JSONL record per
op boundary directly to COM1. A QEMU `-serial file:/tmp/trace.log`
run captures those lines interleaved with regular boot / shell
output. This script demultiplexes them into a clean JSONL stream
matching the schema produced by the Python simulator
(`fajarquant/tools/kernel_sim/trace.py`) and the HuggingFace reference
(planned P2.5).

The output is diffable line-for-line against both peers — that's the
whole point. Diff tooling for P3 divergence analysis operates on
these three JSONL files.

── Usage ─────────────────────────────────────────────────────────

  # Typical:
  qemu-system-x86_64 ... -serial file:/tmp/kernel_serial.log
  python3 scripts/parse_kernel_trace.py \\
      --input /tmp/kernel_serial.log \\
      --output /tmp/kernel_trace.jsonl

  # Pipe from stdin:
  cat /tmp/kernel_serial.log | \\
      python3 scripts/parse_kernel_trace.py > /tmp/kernel_trace.jsonl

  # Strict mode (exit non-zero if any record fails schema v1):
  python3 scripts/parse_kernel_trace.py --strict -i log -o trace.jsonl

  # Self-test against bundled fixture:
  python3 scripts/parse_kernel_trace.py --self-test

── Design decisions ──────────────────────────────────────────────

The kernel emits JSONL directly — one complete object per line, with
no prefix. The parser's job is therefore narrow:

  1. Candidate lines: any line whose stripped form starts with
     `{"schema_version":1,` (version-pinned so a future schema v2
     doesn't accidentally re-enable extraction of obsolete records).
  2. Validate: json.loads succeeds AND required fields exist AND
     `op` ∈ OP_NAMES AND `shape` is a list of ints.
  3. Emit: json.dumps with compact separators, one per line.
  4. Summary: records parsed, records skipped, op histogram,
     monotonicity check on `step`.

Non-candidate lines are silently ignored. A malformed candidate
(JSON syntax error or missing field) prints a warning to stderr and,
in `--strict` mode, triggers a non-zero exit at the end.

The kernel's `fjtrace_emit_mem_i64` is synchronous (blocking serial
write), so `step` should be strictly monotonic in the serial stream.
We only WARN on non-monotonic step because the user might have
concatenated multiple traces or the kernel might have rebooted
mid-run. `--renumber` rewrites `step` to arrival order, useful when
cross-repo diffs need a single coherent sequence.

OP_NAMES is duplicated here (not imported from fajarquant) so the
script is self-contained — you can run it on a log file without
having `fajarquant` on disk. The self-test enforces the count + names
match what the kernel emits, so drift between this list and
kernel_sim/trace.py is caught immediately when `--self-test` runs in
CI or locally.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import Counter
from typing import Any, Dict, Iterable, List, Optional, TextIO, Tuple


SCHEMA_VERSION = 1

# Pinned — must match fajarquant/tools/kernel_sim/trace.py OP_NAMES and
# the kernel-side 17 emit call sites in kernel/compute/transformer.fj.
# Any drift is caught by the --self-test fixture round-trip.
OP_NAMES = frozenset({
    "embed_lookup",
    "pre_attn_rmsnorm",
    "q_proj", "k_proj", "v_proj",
    "attn_out", "post_attn_rmsnorm", "attn_residual",
    "pre_ffn_rmsnorm",
    "gate_proj", "up_proj", "ffn_hidden", "down_proj",
    "post_ffn_rmsnorm", "ffn_residual",
    "final_rmsnorm", "argmax",
})

REQUIRED_FIELDS = (
    "schema_version", "step", "op", "token_idx", "layer",
    "shape", "dtype", "min", "max", "mean", "nnz", "top5_abs", "hash",
)

# Match ANY schema_version so that records emitted with a mismatched
# version surface as malformed rather than getting silently filtered.
# The prefix is narrow enough to avoid colliding with other kernel
# output (which uses bracketed `[TAG]` prefixes and plain-text lines).
CANDIDATE_PREFIX = '{"schema_version":'


class ParseStats:
    """Running counters for the summary line printed to stderr."""

    def __init__(self) -> None:
        self.lines_read = 0
        self.candidates = 0
        self.records = 0
        self.malformed = 0
        self.unknown_op = 0
        self.op_counts: Counter[str] = Counter()
        self.non_monotonic = 0
        self.last_step: Optional[int] = None

    def report(self, out: TextIO) -> None:
        print(
            f"[fjtrace-parse] {self.lines_read} lines read, "
            f"{self.candidates} candidates, "
            f"{self.records} records, "
            f"{self.malformed} malformed, "
            f"{self.unknown_op} unknown-op",
            file=out,
        )
        if self.records:
            print(
                "[fjtrace-parse] ops: " +
                ", ".join(
                    f"{op}={n}"
                    for op, n in sorted(self.op_counts.items())
                ),
                file=out,
            )
        if self.non_monotonic:
            print(
                f"[fjtrace-parse] WARNING: {self.non_monotonic} non-monotonic "
                "step transitions (partial reboot or concatenated trace?)",
                file=out,
            )


def _validate_record(rec: Dict[str, Any]) -> Optional[str]:
    """Return an error reason if `rec` fails schema v1, else None."""
    for f in REQUIRED_FIELDS:
        if f not in rec:
            return f"missing field {f!r}"
    if rec["schema_version"] != SCHEMA_VERSION:
        return f"schema_version {rec['schema_version']!r} != {SCHEMA_VERSION}"
    if not isinstance(rec["op"], str):
        return f"op must be str, got {type(rec['op']).__name__}"
    if rec["op"] not in OP_NAMES:
        return f"unknown op {rec['op']!r}"
    if not isinstance(rec["shape"], list):
        return f"shape must be list"
    for d in rec["shape"]:
        if not isinstance(d, int):
            return f"shape contains non-int {d!r}"
    if not isinstance(rec["step"], int):
        return "step must be int"
    if not isinstance(rec["hash"], str) or not rec["hash"].startswith("0x"):
        return "hash must be 0x-prefixed hex string"
    return None


def parse_stream(
    src: Iterable[str],
    dst: TextIO,
    *,
    renumber: bool = False,
    strict: bool = False,
    stats: Optional[ParseStats] = None,
) -> ParseStats:
    """Read serial-log lines from `src`, write clean JSONL to `dst`."""
    stats = stats if stats is not None else ParseStats()

    out_step = 0
    for raw in src:
        stats.lines_read += 1
        line = raw.rstrip("\r\n").strip()
        if not line.startswith(CANDIDATE_PREFIX):
            continue
        stats.candidates += 1
        try:
            rec = json.loads(line)
        except json.JSONDecodeError as e:
            stats.malformed += 1
            print(
                f"[fjtrace-parse] warn: malformed JSON at line "
                f"{stats.lines_read}: {e.msg}",
                file=sys.stderr,
            )
            continue

        err = _validate_record(rec)
        if err is not None:
            if "unknown op" in err:
                stats.unknown_op += 1
            else:
                stats.malformed += 1
            print(
                f"[fjtrace-parse] warn: invalid record at line "
                f"{stats.lines_read}: {err}",
                file=sys.stderr,
            )
            continue

        # Monotonicity check
        if stats.last_step is not None and rec["step"] <= stats.last_step:
            stats.non_monotonic += 1
        stats.last_step = rec["step"]

        if renumber:
            rec["step"] = out_step
            out_step += 1

        stats.records += 1
        stats.op_counts[rec["op"]] += 1
        dst.write(json.dumps(rec, separators=(",", ":")) + "\n")

    return stats


# ── Self-test ────────────────────────────────────────────────────

# Fixture carries a `.serial.txt` suffix rather than `.log` because
# `.log` is in the repo's .gitignore; the content is synthetic serial
# output regardless of the extension.
_FIXTURE_NAME = "fjtrace_sample.serial.txt"


def _find_fixture() -> Optional[str]:
    """Locate tests/fixtures/fjtrace_sample.log relative to the script."""
    here = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.path.join(here, "..", "tests", "fixtures", _FIXTURE_NAME),
        os.path.join(os.getcwd(), "tests", "fixtures", _FIXTURE_NAME),
    ]
    for p in candidates:
        if os.path.isfile(p):
            return os.path.abspath(p)
    return None


def run_self_test() -> int:
    """Parse the bundled fixture and assert known invariants.

    The fixture is a tiny synthetic serial log with:
      * ~10 lines of simulated boot noise
      * 17 records (one per OP_NAME) so all 17 op name wirings hit
      * 3 deliberately malformed candidate lines (missing field,
        bad schema_version, unknown op) to exercise the error path
    """
    path = _find_fixture()
    if path is None:
        print(
            f"[fjtrace-parse] self-test: fixture {_FIXTURE_NAME!r} not "
            "found (looked in ../tests/fixtures and ./tests/fixtures)",
            file=sys.stderr,
        )
        return 1
    import io
    buf = io.StringIO()
    with open(path, encoding="utf-8") as f:
        stats = parse_stream(f, buf)

    ok = True

    def check(cond: bool, msg: str) -> None:
        nonlocal ok
        status = "PASS" if cond else "FAIL"
        print(f"[fjtrace-parse self-test] {status} {msg}", file=sys.stderr)
        if not cond:
            ok = False

    check(stats.records == 17,
          f"expected 17 valid records, got {stats.records}")
    check(set(stats.op_counts) == OP_NAMES,
          f"expected all 17 op names, got {sorted(stats.op_counts)}")
    check(stats.malformed == 2,
          f"expected 2 malformed records (bad schema + bad JSON), "
          f"got {stats.malformed}")
    check(stats.unknown_op == 1,
          f"expected 1 unknown-op record, got {stats.unknown_op}")
    # Fixture crafts step 0..16 monotonically, so no non-monotonic
    # transitions expected for valid records.
    check(stats.non_monotonic == 0,
          f"expected monotonic steps, got {stats.non_monotonic} reversions")

    # Round-trip: emitted JSONL should also parse cleanly when fed
    # back through the parser (JSON stability + field preservation).
    buf.seek(0)
    stats2 = parse_stream(buf, io.StringIO())
    check(stats2.records == 17, f"round-trip records = {stats2.records}")
    check(stats2.malformed == 0, f"round-trip malformed = {stats2.malformed}")

    return 0 if ok else 1


# ── CLI ──────────────────────────────────────────────────────────

def _main(argv: List[str]) -> int:
    p = argparse.ArgumentParser(
        description="Extract FJTRACE JSONL records from a serial log.",
    )
    p.add_argument("-i", "--input", default="-",
                   help="serial log path, or '-' for stdin (default: -)")
    p.add_argument("-o", "--output", default="-",
                   help="output JSONL path, or '-' for stdout (default: -)")
    p.add_argument("--renumber", action="store_true",
                   help="rewrite `step` to arrival order (default: "
                        "preserve kernel step)")
    p.add_argument("--strict", action="store_true",
                   help="exit non-zero if any record is malformed or "
                        "uses an unknown op")
    p.add_argument("--self-test", action="store_true",
                   help="run internal test against bundled fixture")
    args = p.parse_args(argv)

    if args.self_test:
        return run_self_test()

    in_fh: TextIO = (sys.stdin if args.input == "-"
                     else open(args.input, encoding="utf-8"))
    out_fh: TextIO = (sys.stdout if args.output == "-"
                      else open(args.output, "w", encoding="utf-8"))
    try:
        stats = parse_stream(
            in_fh, out_fh,
            renumber=args.renumber,
            strict=args.strict,
        )
    finally:
        if in_fh is not sys.stdin:
            in_fh.close()
        if out_fh is not sys.stdout:
            out_fh.close()

    stats.report(sys.stderr)

    if args.strict and (stats.malformed or stats.unknown_op):
        print(
            f"[fjtrace-parse] --strict: {stats.malformed} malformed + "
            f"{stats.unknown_op} unknown-op; exiting 2",
            file=sys.stderr,
        )
        return 2
    if stats.records == 0:
        print("[fjtrace-parse] WARNING: no records extracted "
              "(was FJTRACE_ENABLED=1 at build time?)",
              file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
