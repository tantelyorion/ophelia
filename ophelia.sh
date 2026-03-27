#!/usr/bin/env bash
# ============================================================
#                        OPHELIA
#          Folder Structure Generator — v1.0.0
#                   Open Source (MIT)
# ============================================================
# Paste any tree-style folder structure and Ophelia will
# create every file and directory automatically.
#
# Usage:
#   ./ophelia.sh                          interactive mode
#   ./ophelia.sh -i structure.txt         from a file
#   ./ophelia.sh -i s.txt -o ~/myproject  custom output folder
#   ./ophelia.sh --preview                dry-run only
#   ./ophelia.sh --help
# ============================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────
if [ -t 1 ] && command -v tput &>/dev/null; then
    RESET=$(tput sgr0)
    BOLD=$(tput bold)
    DIM=$(tput dim 2>/dev/null || echo "")
    GREEN=$(tput setaf 2)
    CYAN=$(tput setaf 6)
    YELLOW=$(tput setaf 3)
    RED=$(tput setaf 1)
    PURPLE=$(tput setaf 5)
else
    RESET="" BOLD="" DIM="" GREEN="" CYAN="" YELLOW="" RED="" PURPLE=""
fi

# ── Banner ────────────────────────────────────────────────
banner() {
cat <<EOF

${PURPLE}${BOLD}
  ██████╗ ██████╗ ██╗  ██╗███████╗██╗     ██╗ █████╗
 ██╔═══██╗██╔══██╗██║  ██║██╔════╝██║     ██║██╔══██╗
 ██║   ██║██████╔╝███████║█████╗  ██║     ██║███████║
 ██║   ██║██╔═══╝ ██╔══██║██╔══╝  ██║     ██║██╔══██║
 ╚██████╔╝██║     ██║  ██║███████╗███████╗██║██║  ██║
  ╚═════╝ ╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝╚═╝╚═╝  ╚═╝${RESET}
${DIM}  Folder Structure Generator v1.0.0 — Open Source MIT${RESET}
EOF
}

# ── Help ──────────────────────────────────────────────────
show_help() {
cat <<EOF
${BOLD}OPHELIA — Folder Structure Generator${RESET}

${BOLD}Usage:${RESET}
  ./ophelia.sh                            Interactive mode
  ./ophelia.sh -i structure.txt           Read from file
  ./ophelia.sh -i s.txt -o ~/myproject    Custom output folder
  ./ophelia.sh --preview                  Dry-run (no files created)

${BOLD}Supported tree formats:${RESET}
  ├── folder/       Unicode box-drawing (tree, GitHub, AI tools)
  |-- folder/       ASCII pipes
  +-- file.txt      Plus signs
  - file.txt        Bullets / dashes
  folder/           Plain indentation

${BOLD}Rules:${RESET}
  - Names ending with /  →  directory
  - Names with a dot extension  →  file
  - Comments in parentheses are ignored:  uploads/ (for photos)

${BOLD}Make executable:${RESET}
  chmod +x ophelia.sh

EOF
}

# ── Detect Python ─────────────────────────────────────────
find_python() {
    for cmd in python3 python python3.12 python3.11 python3.10; do
        if command -v "$cmd" &>/dev/null; then
            local ver
            ver=$("$cmd" -c "import sys; print(sys.version_info.major)" 2>/dev/null)
            if [ "${ver:-0}" -ge 3 ]; then
                echo "$cmd"
                return 0
            fi
        fi
    done
    return 1
}

# ── Python engine (heredoc, inline) ───────────────────────
run_engine() {
    local struct_file="$1"
    local output_dir="$2"
    local preview="$3"   # "1" = preview only, "0" = create

    local PYTHON
    PYTHON=$(find_python) || {
        echo "${RED}[ERROR]${RESET} Python 3 is not installed."
        echo "Install it from https://python.org or via your package manager."
        exit 1
    }

    "$PYTHON" - "$struct_file" "$output_dir" "$preview" <<'PYEOF'
import sys, re
from pathlib import Path

def strip_prefix(line):
    """Remove all tree-drawing decoration from the start of a line."""
    # Leading whitespace + vertical bar characters
    line = re.sub(r'^[\s\u2502\u2503\|]*', '', line)
    # Tree branch characters + dashes
    line = re.sub(r'^[\u251C\u2514\u2560\u255A\|+`][\u2500\-]+\s*', '', line)
    # Bullet / asterisk / plus
    line = re.sub(r'^[\-\*\+]\s+', '', line)
    return line

def leading_depth_chars(line):
    """Count the number of leading structural characters (spaces + pipes)."""
    m = re.match(r'^[\s\u2502\u2503\|]*', line)
    return len(m.group(0)) if m else 0

def parse(raw):
    lines = [l.rstrip() for l in raw.splitlines() if l.strip()]
    # Drop pure separator / decoration lines
    lines = [l for l in lines if not re.match(
        r'^[\s\u2500\u2502\u251C\u2514\u2560\u255A\|=\-]+$', l)]
    if not lines:
        return []

    # Auto-detect indentation unit
    depths = [leading_depth_chars(l) for l in lines]
    deltas = sorted({b - a for a, b in zip(depths, depths[1:]) if b > a})
    unit = deltas[0] if deltas else 4

    entries = []
    for line in lines:
        depth = leading_depth_chars(line) // max(unit, 1)
        name  = strip_prefix(line).strip()
        # Strip inline comments like (pour les photos)
        name  = re.sub(r'\s*\(.*?\)\s*$', '', name).strip()
        if not name or re.match(r'^[\-=\u2500]+$', name):
            continue
        is_dir = name.endswith('/')
        if is_dir:
            name = name[:-1]
        entries.append((depth, name, is_dir))
    return entries

def build(entries):
    stack, result = [], []
    for depth, name, is_dir in entries:
        stack = stack[:depth]
        p = Path(*stack, name) if stack else Path(name)
        result.append((p, is_dir))
        if is_dir:
            stack.append(name)
    return result

struct_path = sys.argv[1]
output_dir  = sys.argv[2]
preview     = (sys.argv[3] == '1')

raw     = Path(struct_path).read_text(encoding='utf-8', errors='replace')
entries = parse(raw)

if not entries:
    print('ERROR: Could not parse any entries from the input.')
    print('Make sure the structure uses standard tree notation.')
    sys.exit(1)

paths = build(entries)
root  = Path(output_dir)

# Preview
print(f'\nPreview  [root: {root}]')
print('─' * 52)
for rel, is_dir in paths:
    pad    = '  ' * len(rel.parts)
    tag    = '[DIR] ' if is_dir else '[FILE]'
    suffix = '/'    if is_dir else ''
    print(f'{pad}{tag} {rel.name}{suffix}')

nd = sum(1 for _, d in paths if d)
nf = len(paths) - nd
print(f'\nTotal: {nd} director{"ies" if nd != 1 else "y"}, {nf} file{"s" if nf != 1 else ""}')

if not preview:
    root.mkdir(parents=True, exist_ok=True)
    ok_d, ok_f, errs = 0, 0, []
    for rel, is_dir in paths:
        full = root / rel
        try:
            if is_dir:
                full.mkdir(parents=True, exist_ok=True)
                ok_d += 1
                print(f'  [OK-DIR]  {rel}/')
            else:
                full.parent.mkdir(parents=True, exist_ok=True)
                if not full.exists():
                    full.touch()
                ok_f += 1
                print(f'  [OK-FILE] {rel}')
        except OSError as e:
            errs.append(str(e))
            print(f'  [ERR]     {rel}: {e}')

    print()
    print(f'Done!  {ok_d} dir{"s" if ok_d != 1 else ""} + {ok_f} file{"s" if ok_f != 1 else ""} created in: {root}')
    if errs:
        print(f'Errors ({len(errs)}):')
        for e in errs:
            print(f'  x {e}')
PYEOF
}

# ── Argument parsing ──────────────────────────────────────
INPUT_FILE=""
OUTPUT_DIR=""
PREVIEW=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--input)   INPUT_FILE="$2"; shift 2 ;;
        -o|--output)  OUTPUT_DIR="$2"; shift 2 ;;
        --preview)    PREVIEW=1; shift ;;
        -h|--help)    banner; show_help; exit 0 ;;
        *)            shift ;;
    esac
done

banner

# ── Temp file ─────────────────────────────────────────────
TMP_DIR=$(mktemp -d "/tmp/ophelia_XXXXXX")
STRUCT_FILE="$TMP_DIR/structure.txt"
trap 'rm -rf "$TMP_DIR"' EXIT

# ── Get input ─────────────────────────────────────────────
if [[ -n "$INPUT_FILE" ]]; then
    if [[ ! -f "$INPUT_FILE" ]]; then
        echo "${RED}[ERROR]${RESET} File not found: $INPUT_FILE"
        exit 1
    fi
    cp "$INPUT_FILE" "$STRUCT_FILE"
    echo "${DIM}Reading from: $INPUT_FILE${RESET}"
    echo
else
    echo "${CYAN}${BOLD}Paste your folder structure below.${RESET}"
    echo "${DIM}When done, type END on its own line and press Enter.${RESET}"
    echo

    while IFS= read -r line; do
        [[ "${line^^}" == "END" ]] && break
        printf '%s\n' "$line" >> "$STRUCT_FILE"
    done
    echo
fi

# Check not empty
if [[ ! -s "$STRUCT_FILE" ]]; then
    echo "${YELLOW}Nothing to do — empty input.${RESET}"
    exit 0
fi

# ── Output dir ────────────────────────────────────────────
if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="$(pwd)"
fi
OUTPUT_DIR="${OUTPUT_DIR%/}"   # trim trailing slash

# ── Preview pass ──────────────────────────────────────────
if ! run_engine "$STRUCT_FILE" "$OUTPUT_DIR" "1"; then
    exit 1
fi

echo

if [[ $PREVIEW -eq 1 ]]; then
    echo "${YELLOW}[DRY-RUN] No files or directories were created.${RESET}"
    exit 0
fi

# ── Confirm ───────────────────────────────────────────────
echo "${BOLD}Output: ${CYAN}$OUTPUT_DIR${RESET}"
echo
printf "${BOLD}Create structure? [Y/n]${RESET}  "
read -r CONFIRM </dev/tty
CONFIRM="${CONFIRM,,}"

if [[ "$CONFIRM" == "n" || "$CONFIRM" == "no" || "$CONFIRM" == "non" ]]; then
    echo
    echo "${YELLOW}Aborted. Nothing was created.${RESET}"
    exit 0
fi

echo
if ! run_engine "$STRUCT_FILE" "$OUTPUT_DIR" "0"; then
    exit 1
fi

echo
echo "${GREEN}${BOLD}All done!${RESET} Structure created in: ${CYAN}$OUTPUT_DIR${RESET}"
echo
