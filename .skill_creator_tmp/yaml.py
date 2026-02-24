"""Minimal YAML compatibility shim for offline skill-creator scripts.

Supports only simple mapping documents with scalar values.
"""


class YAMLError(Exception):
    """Compatibility exception type."""


def _strip_comments(line):
    in_single = False
    in_double = False
    out = []
    for ch in line:
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
        elif ch == "#" and not in_single and not in_double:
            break
        out.append(ch)
    return "".join(out).rstrip()


def _parse_scalar(value):
    value = value.strip()
    if not value:
        return ""
    if (value.startswith('"') and value.endswith('"')) or (
        value.startswith("'") and value.endswith("'")
    ):
        return value[1:-1]
    lowered = value.lower()
    if lowered in ("true", "false"):
        return lowered == "true"
    if lowered in ("null", "~"):
        return None
    if value.isdigit():
        return int(value)
    try:
        return float(value)
    except ValueError:
        return value


def safe_load(text):
    if not isinstance(text, str):
        raise YAMLError("safe_load expects a string")
    root = {}
    stack = [(-1, root)]
    for raw in text.splitlines():
        if not raw.strip():
            continue
        line = _strip_comments(raw)
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip(" "))
        if line.lstrip(" ").startswith("- "):
            raise YAMLError("lists are not supported by this shim")
        stripped = line.strip()
        if ":" not in stripped:
            raise YAMLError(f"invalid mapping line: {raw}")
        key, value = stripped.split(":", 1)
        key = key.strip()
        if not key:
            raise YAMLError("empty key")
        while stack and indent <= stack[-1][0]:
            stack.pop()
        if not stack:
            raise YAMLError("invalid indentation")
        parent = stack[-1][1]
        if not isinstance(parent, dict):
            raise YAMLError("invalid parent container")
        if value.strip() == "":
            node = {}
            parent[key] = node
            stack.append((indent, node))
        else:
            parent[key] = _parse_scalar(value)
    return root

