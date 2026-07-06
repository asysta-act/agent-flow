# hooks/lib/witness_key.py
# Per-run key lifecycle + forge-resistant bootstrap predicate for the
# gate-as-signer dispatch witness (PR #15).
#
# This module is the SOLE key generator/reader for the keyed witness. It is
# imported (or shelled to) by the PreToolUse gate (hooks/validate-dispatch-pre.sh)
# and by the demoted bash self-test (core/lib/stage-invariant.sh --self-test).
# The orchestrator NEVER holds the key (REQ-001 / REQ-002): only the gate calls
# generate_key().
#
# Contract (byte-pinned by design.md §3.2 / §3.11, REQ-006..REQ-009, REQ-047):
#   * Key = 64 lowercase-hex chars (secrets.token_hex(32), 256-bit CSPRNG).
#   * Created ATOMICALLY with mode 0600 via
#       os.open(path, O_WRONLY|O_CREAT|O_EXCL, 0o600)  then write
#     (no generate-to-stdout-then-chmod umask window). O_EXCL means a second
#     create at the same path fails -> never a silent re-sign over a present key.
#     POSIX boundary; degrades to best-effort NTFS ACL on Windows/MSYS2.
#   * The key is the sibling of state.json: <dirname(state_json)>/dispatch.key.
#     AGENT_FLOW_DISPATCH_KEY_FILE overrides the PATH only (never the value).
#   * The key is NEVER written to state.json, the ledger, the audit log, any
#     prompt, or any error message. It is returned in-process to the caller, and
#     the CLI emits it ONLY on stdout (for the gate to capture), never to a log.
#
# Forge-resistant bootstrap predicate (REQ-047 / REQ-008):
#   key present  + "2.0" + any            + any        -> KEYED
#   key absent   + "2.0" + ZERO completed + empty ledg -> GENERATE (row i: once)
#   key absent   + "2.0" + >=1 completed  OR non-empty -> WITNESS_UNVERIFIABLE
#                                                          (row d: NEVER regen)
#   key absent   + "1.0"/unset                          -> LEGACY (pass-through)
#   Requiring BOTH zero-completed-stages AND empty ledger is what makes the
#   bootstrap non-forgeable by ledger truncation alone (the f-c570b4 attack):
#   `rm dispatch.key dispatch-ledger.jsonl` fakes an empty ledger but cannot
#   fabricate zero completed stages in the orchestrator-owned state.json.
#
# Stdlib only: os, json, secrets. No third-party imports.

import os
import json
import secrets

KEY_FILENAME = "dispatch.key"

# Bootstrap-decision verdicts (string sentinels the gate dispatches on).
DECISION_KEYED = "KEYED"                         # key present -> keyed verify
DECISION_GENERATE = "GENERATE"                   # genuine first intercept (row i)
DECISION_UNVERIFIABLE = "WITNESS_UNVERIFIABLE"   # key lost on progressed run (row d)
DECISION_LEGACY = "LEGACY"                        # legacy v1.0 keyless pass-through


def generate_key(path):
    """Atomically create the per-run key file (REQ-006) and return the key hex.

    64 lowercase-hex (secrets.token_hex(32)) written via
    os.open(O_WRONLY|O_CREAT|O_EXCL, 0o600) then write -- no umask window, and
    O_EXCL guarantees we never overwrite an existing key (no silent re-sign).
    Raises OSError (incl. FileExistsError / NotADirectoryError /
    FileNotFoundError) on any failure so the gate can fail closed (REQ-008);
    the key value is never placed in the exception text.
    """
    keyhex = secrets.token_hex(32)  # exactly 64 lowercase hex chars
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        os.write(fd, keyhex.encode("ascii"))
    finally:
        os.close(fd)
    return keyhex


def read_key(path):
    """Return the stripped key hex from PATH, or None if absent/empty/unreadable.

    Readers .strip() trailing whitespace/newlines (design.md §3.2). A missing or
    empty file yields None (treated as "no usable key" by bootstrap_decision).
    """
    try:
        with open(path, encoding="utf-8") as f:
            k = f.read().strip()
    except (FileNotFoundError, NotADirectoryError, IsADirectoryError, OSError):
        return None
    return k or None


def discover_key(state_json):
    """Resolve the key file path for a run (REQ-007).

    AGENT_FLOW_DISPATCH_KEY_FILE overrides the PATH (never the value); otherwise
    the key is the sibling of state.json (<dirname>/dispatch.key).
    """
    override = os.environ.get("AGENT_FLOW_DISPATCH_KEY_FILE")
    if override:
        return override
    return os.path.join(os.path.dirname(state_json), KEY_FILENAME)


def _load_state(state_json):
    """Best-effort json.load of state.json; {} on any error (treat as no run)."""
    try:
        with open(state_json, encoding="utf-8") as f:
            return json.load(f) or {}
    except Exception:
        return {}


def schema_version(state_json):
    """Top-level schema_version string ("" if absent/unreadable)."""
    return str(_load_state(state_json).get("schema_version") or "")


def count_completed_stages(state_json):
    """Count stages whose status == "completed" (REQ-047 fresh-run predicate).

    "completed (non-skipped)" stage claims: an in_progress stage (the one being
    dispatched now) and a skipped stage do NOT count. This is the positive
    fresh-run signal a ledger truncation cannot fabricate.
    """
    stages = _load_state(state_json).get("stages") or {}
    if not isinstance(stages, dict):
        return 0
    n = 0
    for s in stages.values():
        if isinstance(s, dict) and s.get("status") == "completed":
            n += 1
    return n


def ledger_is_nonempty(ledger_path):
    """True iff the ledger file exists and has at least one non-blank line."""
    try:
        with open(ledger_path, encoding="utf-8") as f:
            for line in f:
                if line.strip():
                    return True
    except (FileNotFoundError, NotADirectoryError, IsADirectoryError, OSError):
        return False
    return False


def decide(key_present, schema_ver, completed_stages, ledger_nonempty):
    """Pure bootstrap decision (no I/O) -- the forge-resistant tree of REQ-047.

    Inputs are already-resolved booleans/ints so the predicate is unit-testable
    independently of the filesystem.
    """
    if key_present:
        return DECISION_KEYED
    # key absent from here on.
    if schema_ver == "2.0":
        if completed_stages == 0 and not ledger_nonempty:
            return DECISION_GENERATE          # row i: genuine first intercept
        return DECISION_UNVERIFIABLE          # row d: progressed run, key lost
    # schema "1.0" / unset -> legacy keyless contract; gate passes through.
    return DECISION_LEGACY


def bootstrap_decision(key_path, state_json, ledger_path):
    """Resolve the bootstrap decision from on-disk state (REQ-008 / REQ-047).

    Returns one of KEYED / GENERATE / WITNESS_UNVERIFIABLE / LEGACY. The gate:
      KEYED              -> read key, keyed verify (compare -> sign or DENY)
      GENERATE           -> generate_key() once, then keyed verify
      WITNESS_UNVERIFIABLE -> DENY (+ exit 2 under strict); NEVER regenerate
      LEGACY             -> pass through to the audit's sha256 dual-mode
    """
    key_present = read_key(key_path) is not None
    return decide(
        key_present,
        schema_version(state_json),
        count_completed_stages(state_json),
        ledger_is_nonempty(ledger_path),
    )


def _self_test():
    """Non-authoritative self-check exercising the key lifecycle + predicate."""
    import re
    import tempfile

    ok = True
    work = tempfile.mkdtemp(prefix="wk_")

    # generate_key -> 64 lowercase hex, atomic, readable back, O_EXCL re-create.
    kp = os.path.join(work, "dispatch.key")
    k1 = generate_key(kp)
    ok = ok and bool(re.match(r"^[0-9a-f]{64}$", k1))
    ok = ok and (read_key(kp) == k1)
    try:
        generate_key(kp)          # O_EXCL must reject a second create.
        ok = False
    except OSError:
        pass

    # mode 0600 where the platform reports it (POSIX; NTFS degrades).
    try:
        mode = os.stat(kp).st_mode & 0o777
        if os.name == "posix":
            ok = ok and (mode == 0o600)
    except OSError:
        pass

    # rotation: a second path yields a DIFFERENT key.
    kp2 = os.path.join(work, "two", "dispatch.key")
    os.makedirs(os.path.dirname(kp2), exist_ok=True)
    k2 = generate_key(kp2)
    ok = ok and (k1 != k2)

    # read_key on an absent path -> None.
    ok = ok and (read_key(os.path.join(work, "nope.key")) is None)

    # discover_key: sibling resolution + env override.
    sj = os.path.join(work, "rundir", "state.json")
    saved = os.environ.pop("AGENT_FLOW_DISPATCH_KEY_FILE", None)
    try:
        ok = ok and (discover_key(sj) == os.path.join(work, "rundir", "dispatch.key"))
        os.environ["AGENT_FLOW_DISPATCH_KEY_FILE"] = "/tmp/override.key"
        ok = ok and (discover_key(sj) == "/tmp/override.key")
    finally:
        os.environ.pop("AGENT_FLOW_DISPATCH_KEY_FILE", None)
        if saved is not None:
            os.environ["AGENT_FLOW_DISPATCH_KEY_FILE"] = saved

    # pure predicate: the four bootstrap branches.
    ok = ok and (decide(True, "2.0", 5, True) == DECISION_KEYED)
    ok = ok and (decide(False, "2.0", 0, False) == DECISION_GENERATE)
    ok = ok and (decide(False, "2.0", 1, False) == DECISION_UNVERIFIABLE)
    ok = ok and (decide(False, "2.0", 0, True) == DECISION_UNVERIFIABLE)
    ok = ok and (decide(False, "1.0", 0, False) == DECISION_LEGACY)
    ok = ok and (decide(False, "", 9, True) == DECISION_LEGACY)

    # bootstrap_decision end-to-end against written state files.
    rd = os.path.join(work, "bd")
    os.makedirs(rd, exist_ok=True)
    sjp = os.path.join(rd, "state.json")
    ledp = os.path.join(rd, "dispatch-ledger.jsonl")
    fresh = {"schema_version": "2.0",
             "stages": {"triage": {"status": "in_progress"}}}
    open(sjp, "w", encoding="utf-8").write(json.dumps(fresh))
    ok = ok and (bootstrap_decision(os.path.join(rd, "dispatch.key"), sjp, ledp)
                 == DECISION_GENERATE)
    progressed = {"schema_version": "2.0",
                  "stages": {"triage": {"status": "completed"},
                             "fixer_reviewer": {"status": "in_progress"}}}
    open(sjp, "w", encoding="utf-8").write(json.dumps(progressed))
    ok = ok and (bootstrap_decision(os.path.join(rd, "dispatch.key"), sjp, ledp)
                 == DECISION_UNVERIFIABLE)

    try:
        import shutil
        shutil.rmtree(work, ignore_errors=True)
    except Exception:
        pass
    return ok


if __name__ == "__main__":
    # CLI for bash callers (the gate / the demoted --self-test). The key value
    # is emitted ONLY on stdout (never a log/error path).
    #   witness_key.py generate KEYPATH          -> create key, print hex
    #   witness_key.py read KEYPATH              -> print hex (or empty)
    #   witness_key.py discover STATE_JSON       -> print resolved key path
    #   witness_key.py bootstrap KEY STATE LEDGER-> print decision
    #   witness_key.py --self-test
    import sys

    args = sys.argv[1:]
    cmd = args[0] if args else ""
    if cmd == "generate" and len(args) == 2:
        try:
            sys.stdout.write(generate_key(args[1]))
        except OSError:
            # Fail closed WITHOUT leaking the key or a path-bearing trace.
            sys.stderr.write("witness_key: key generation failed\n")
            sys.exit(1)
    elif cmd == "read" and len(args) == 2:
        sys.stdout.write(read_key(args[1]) or "")
    elif cmd == "discover" and len(args) == 2:
        sys.stdout.write(discover_key(args[1]))
    elif cmd == "bootstrap" and len(args) == 4:
        sys.stdout.write(bootstrap_decision(args[1], args[2], args[3]))
    elif cmd == "--self-test":
        passed = _self_test()
        sys.stdout.write("self-test: PASS\n" if passed else "self-test: FAIL\n")
        sys.exit(0 if passed else 1)
    else:
        sys.stderr.write(
            "usage: witness_key.py {generate KEYPATH | read KEYPATH | "
            "discover STATE_JSON | bootstrap KEY STATE LEDGER | --self-test}\n"
        )
        sys.exit(2)
