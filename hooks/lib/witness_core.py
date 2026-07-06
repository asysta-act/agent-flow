# hooks/lib/witness_core.py
# Shared keyed-witness primitive for the gate-as-signer dispatch witness (PR #15).
#
# Single source of truth for the keyed construction. BOTH hooks
# (hooks/validate-dispatch-pre.sh PreToolUse gate + hooks/validate-dispatch.sh
# PostToolUse audit) exec/import these functions so the canon/tag/head128
# definitions exist in exactly ONE runtime (Python). Bash holds NO keyed path
# (REQ-010 / REQ-030).
#
# Contract is byte-pinned by design.md Layer-2 section 3.1 / 3.13:
#   canon = sha256(subagent_type) | sha256(model) | sha256(prompt_head_128)
#           | sha256(overlay_source) | sha256(overlay_digest)
#           | sha256(stage) | sha256(run_id) | sha256(claim_nonce)
#   tag   = HMAC_SHA256( key = ASCII_bytes(KEYHEX), msg = canon )   # 64 lc hex
#
# Pinned rules (do NOT "optimize" — these are MSYS2<->Linux byte-identity locks):
#   * _h(x): sha256 of LF-normalized (CRLF/CR -> LF), UTF-8 encoded field with
#     NO trailing newline. Each sub-hash is fixed-length [0-9a-f]{64} so the
#     literal "|" join can never be ambiguous (closes C8 delimiter injection).
#   * Option-A key handling: HMAC key is the literal ASCII bytes of the 64-hex
#     KEY STRING (keyhex.encode("ascii")) -- NEVER bytes.fromhex(keyhex)
#     (REQ-012; the one reproduced rawkey-vs-hexkey divergence).
#   * head128(p): LF-normalize -> UTF-8 encode -> first 128 BYTES -> drop a
#     trailing partial codepoint (decode utf-8 "ignore"). Order is normative
#     (REQ-051). The first canon field is ALWAYS the full namespace-prefixed
#     subagent_type (e.g. "agent-flow:analyst"); the short name is NEVER hashed.
#
# Stdlib only: hmac, hashlib. No third-party imports.

import hmac
import hashlib

# Algorithm/version envelope. Names {MAC algorithm + canonicalization scheme}.
# Display/audit HINT only -- the security authority for "is this run keyed" is
# the presence of the 0600 dispatch.key file, never this string (REQ-013).
dispatch_witness_alg = "hmac-sha256-subhash-v1"


def _h(x):
    """sha256 hex of the LF-normalized, UTF-8-encoded field, no trailing newline."""
    return hashlib.sha256(
        x.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")
    ).hexdigest()


def head128(p):
    """Canonical observed prompt head (REQ-051).

    Order is normative: LF-normalize -> UTF-8 encode -> first 128 bytes ->
    drop a trailing partial codepoint. Computed by the GATE from
    tool_input.prompt and signed as ground truth (never an orchestrator claim).
    """
    b = p.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")[:128]
    return b.decode("utf-8", "ignore")


def canon(subagent_type, model, prompt_head_128, overlay_source, overlay_digest,
          stage, run_id, claim_nonce):
    """Per-field sub-hashing preimage; literal "|" join (REQ-011).

    subagent_type MUST be the full namespace-prefixed identity string; the
    short name is used only for on-disk lookups, never hashed.
    """
    return "|".join(
        _h(v) for v in (
            subagent_type, model, prompt_head_128, overlay_source,
            overlay_digest, stage, run_id, claim_nonce,
        )
    )


def tag(keyhex, c):
    """HMAC-SHA256 over the canon preimage; Option-A key handling (REQ-012).

    key = ASCII bytes of the 64-hex KEY STRING (NEVER bytes.fromhex).
    """
    return hmac.new(keyhex.encode("ascii"), c.encode("utf-8"), hashlib.sha256).hexdigest()


if __name__ == "__main__":
    # Non-authoritative self-check / parity helper. Usage:
    #   python witness_core.py --self-test
    #   python witness_core.py head128       (reads prompt on stdin, writes head)
    #   python witness_core.py tag KEYHEX f1 f2 f3 f4 f5 f6 f7 f8
    import sys

    args = sys.argv[1:]
    if args and args[0] == "--self-test":
        # Golden known-answer pinned by witness-keyed-parity.sh Part B0.
        KEYHEX = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
        GOLDEN = "2d98801abf01170d1a33478399a96740e92d234ba8d646b67847ed07dec9b735"
        c = canon("agent-flow:fixer", "opus", "PROMPT_HEAD_fixer_reviewer",
                  "none", "none", "fixer_reviewer",
                  "PROJ-42_20260418T133000Z",
                  "0123456789abcdef0123456789abcdef")
        got = tag(KEYHEX, c)
        ok = (got == GOLDEN)
        # head128 mid-codepoint golden: 127*'x' + 'é' -> 127*'x'.
        h = head128("x" * 127 + "é")
        ok = ok and (h == "x" * 127)
        sys.stdout.write("self-test: PASS\n" if ok else "self-test: FAIL\n")
        sys.exit(0 if ok else 1)
    elif args and args[0] == "head128":
        data = sys.stdin.buffer.read().decode("utf-8", "replace")
        sys.stdout.buffer.write(head128(data).encode("utf-8"))
    elif args and args[0] == "tag" and len(args) == 10:
        sys.stdout.write(tag(args[1], canon(*args[2:10])))
    else:
        sys.stderr.write(
            "usage: witness_core.py {--self-test | head128 | "
            "tag KEYHEX f1..f8}\n"
        )
        sys.exit(2)
