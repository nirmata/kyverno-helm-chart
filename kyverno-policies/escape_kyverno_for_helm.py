#!/usr/bin/env python3
"""Escape Kyverno {{ ... }} JMESPath so Helm leaves literal {{ for the API server.

Limitation: policies with multiline quoted strings where `}}` appears after a line
continuation (e.g. check-ephmeral-storage-capacity.yaml) must be escaped by hand;
see git history for a working template.
"""
from __future__ import annotations

import sys
from pathlib import Path

HELM_OPEN = '{{ "{{" }}'
HELM_CLOSE = '{{ "}}" }}'


def skip_escaped_block(text: str, i: int) -> int | None:
    """If position i starts an escaped Helm literal, return index after the block; else None."""
    if not text.startswith(HELM_OPEN, i):
        return None
    j = i + len(HELM_OPEN)
    while j < len(text):
        if text.startswith(HELM_CLOSE, j):
            return j + len(HELM_CLOSE)
        j += 1
    return None


def extract_raw_kyverno_span(text: str, start: int) -> tuple[int, int] | None:
    """Balanced {{ }} from start; does not cross escaped Helm literal blocks."""
    if start + 2 > len(text) or text[start : start + 2] != "{{":
        return None
    depth = 1
    k = start + 2
    while k < len(text) and depth > 0:
        sk = skip_escaped_block(text, k)
        if sk is not None:
            k = sk
            continue
        if text[k : k + 2] == "{{":
            depth += 1
            k += 2
        elif text[k : k + 2] == "}}":
            depth -= 1
            k += 2
        else:
            k += 1
    if depth == 0:
        return start, k
    return None


def collect_innermost_raw_spans(text: str) -> list[tuple[int, int]]:
    """Spans whose inner text contains no unescaped {{ (after skipping Helm literals)."""
    out: list[tuple[int, int]] = []
    i = 0
    while i < len(text):
        sk = skip_escaped_block(text, i)
        if sk is not None:
            i = sk
            continue
        if text[i : i + 2] == "{{":
            sp = extract_raw_kyverno_span(text, i)
            if not sp:
                i += 1
                continue
            s, e = sp
            inner = text[s + 2 : e - 2]
            if _inner_has_raw_kyverno(inner):
                out.extend(
                    (s + 2 + a, s + 2 + b)
                    for a, b in collect_innermost_raw_spans(inner)
                )
            else:
                out.append((s, e))
            i = e
        else:
            i += 1
    return out


def _inner_has_raw_kyverno(inner: str) -> bool:
    i = 0
    while i < len(inner):
        sk = skip_escaped_block(inner, i)
        if sk is not None:
            i = sk
            continue
        if inner[i : i + 2] == "{{":
            return True
        i += 1
    return False


def escape_kyverno_for_helm(text: str) -> str:
    for _ in range(10000):
        spans = collect_innermost_raw_spans(text)
        if not spans:
            break
        for s, e in sorted(spans, key=lambda x: -x[0]):
            inner = text[s + 2 : e - 2].strip()
            repl = HELM_OPEN + " " + inner + " " + HELM_CLOSE
            text = text[:s] + repl + text[e:]
    else:
        raise RuntimeError("escape_kyverno_for_helm: too many iterations")
    return text


def main() -> None:
    root = Path(__file__).resolve().parent / "templates"
    for path in sorted(root.glob("*.yaml")):
        raw = path.read_text()
        new = escape_kyverno_for_helm(raw)
        if new != raw:
            path.write_text(new)
            print(path.name)
    print("done", file=sys.stderr)


if __name__ == "__main__":
    main()
