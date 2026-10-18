"""Check explicit GDScript annotations and the project's no-ternary rule.

Run: python3 tests/check_gdscript_conventions.py
Vendor addons, reference sources, and the phased platoon controller are excluded.
Property setters use the type supplied by their property, as required by GDScript.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
EXCLUDED_DIRS = {".git", ".godot", "addons", "sources"}
EXCLUDED_PHASE_CONTROLLER = Path("ai/platoon/phased/platoon_phase_controller.gd")


def mask_non_code(source: str) -> str:
    """Preserve offsets and newlines while masking strings and comments."""
    result = list(source)
    index = 0
    while index < len(source):
        char = source[index]
        if char == "#":
            end = source.find("\n", index)
            if end == -1:
                end = len(source)
        elif char in "\"'":
            delimiter = char
            if source.startswith(char * 3, index):
                delimiter = char * 3
            end = index + len(delimiter)
            while end < len(source):
                if source[end] == "\\":
                    end += 2
                elif source.startswith(delimiter, end):
                    end += len(delimiter)
                    break
                else:
                    end += 1
        else:
            index += 1
            continue
        for position in range(index, min(end, len(source))):
            if source[position] != "\n":
                result[position] = " "
        index = end
    return "".join(result)


def parameters(arguments: str) -> list[str]:
    parts = []
    start = 0
    depth = 0
    for index, char in enumerate(arguments):
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        elif char == "," and depth == 0:
            parts.append(arguments[start:index])
            start = index + 1
    parts.append(arguments[start:])
    return [part.strip() for part in parts if part.strip()]


def violations(source: str) -> list[tuple[int, str]]:
    code = mask_non_code(source)
    found = []
    for line_number, line in enumerate(code.splitlines(), 1):
        if re.search(r"\b(?:var|const)\s+\w+\s*(?::=|=|$)", line):
            found.append((line_number, "Variable or constant needs a named type"))
        if re.search(r"\bfor\s+\w+\s+in\b", line):
            found.append((line_number, "Loop variable needs a named type"))
        if re.search(r"\bif\b.+\belse\b", line):
            found.append((line_number, "Ternary expression is forbidden"))
    for match in re.finditer(r"\b(func|signal)\s*(\w+)?\s*\(", code):
        kind, name = match.groups()
        start = match.end()
        end = start
        depth = 1
        while end < len(code) and depth:
            if code[end] == "(":
                depth += 1
            elif code[end] == ")":
                depth -= 1
            end += 1
        if depth:
            continue  # Godot's parser reports malformed signatures.
        line_number = code.count("\n", 0, match.start()) + 1
        for argument in parameters(code[start:end - 1]):
            declaration = argument.split("=", 1)[0]
            if ":" not in declaration:
                found.append((line_number, f"{kind} {name or '<lambda>'}: parameter needs a named type"))
        if kind == "func" and not code[end:].lstrip().startswith("->"):
            found.append((line_number, f"Function {name or '<lambda>'} needs a return annotation"))
    return found


def main() -> int:
    # Exercise masking and signatures so comments, strings, and nested defaults
    # cannot make an untyped declaration appear compliant.
    assert not violations('var x: int = 1 # var bad = 2\nfunc f(a: int = int(1)) -> void:\n\tpass\n')
    assert not violations('var text: String = "var x = 1 if a else 2"\n')
    assert len(violations('var x := 1\nfunc f(a):\n\tvar y = 1 if a else 2\n')) == 5
    count = 0
    failures = 0
    for path in sorted(ROOT.rglob("*.gd")):
        relative = path.relative_to(ROOT)
        if set(relative.parts) & EXCLUDED_DIRS or relative == EXCLUDED_PHASE_CONTROLLER:
            continue
        count += 1
        for line, message in violations(path.read_text()):
            print(f"{relative}:{line}: {message}")
            failures += 1
    print(f"Checked {count} project scripts; convention violations: {failures}")
    return int(failures > 0)


if __name__ == "__main__":
    sys.exit(main())
