#!/usr/bin/env python3
"""
╔═══════════════════════════════════════════════════════════╗
║                        OPHELIA                           ║
║          Folder Structure Generator — v1.0.0             ║
║                   Open Source (MIT)                      ║
╚═══════════════════════════════════════════════════════════╝

Paste any tree-style folder structure and Ophelia will
create every file and directory automatically.

Supported styles:
  ├── folder/         (Unicode box-drawing)
  |-- folder/         (ASCII pipes)
  +-- folder/         (plus signs)
  - folder/           (dashes/bullets)
  * folder/           (asterisks)
  folder/             (plain indentation)

Usage:
  python ophelia.py                        # interactive mode
  python ophelia.py -i structure.txt       # from file
  python ophelia.py -i structure.txt -o /my/output/path
  python ophelia.py --preview              # dry-run (no files created)
"""

import os
import re
import sys
import argparse
from pathlib import Path


# ─── ANSI Colors ───────────────────────────────────────────
class C:
    RESET  = "\033[0m"
    BOLD   = "\033[1m"
    DIM    = "\033[2m"
    GREEN  = "\033[32m"
    CYAN   = "\033[36m"
    YELLOW = "\033[33m"
    RED    = "\033[31m"
    BLUE   = "\033[34m"
    PURPLE = "\033[35m"
    WHITE  = "\033[97m"

def no_color():
    """Disable color output (e.g., when piped)."""
    for attr in vars(C):
        if not attr.startswith("_"):
            setattr(C, attr, "")

if not sys.stdout.isatty():
    no_color()


# ─── Banner ────────────────────────────────────────────────
BANNER = f"""
{C.PURPLE}{C.BOLD}
  ██████╗ ██████╗ ██╗  ██╗███████╗██╗     ██╗ █████╗
 ██╔═══██╗██╔══██╗██║  ██║██╔════╝██║     ██║██╔══██╗
 ██║   ██║██████╔╝███████║█████╗  ██║     ██║███████║
 ██║   ██║██╔═══╝ ██╔══██║██╔══╝  ██║     ██║██╔══██║
 ╚██████╔╝██║     ██║  ██║███████╗███████╗██║██║  ██║
  ╚═════╝ ╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝╚═╝╚═╝  ╚═╝
{C.RESET}{C.DIM}  Folder Structure Generator — v1.0.0 — Open Source (MIT){C.RESET}
"""


# ─── Parser ────────────────────────────────────────────────

# Regex strips any tree-style prefix and captures the entry name
# Handles: ├──, └──, |─, ├─, +─, *, -, and plain spaces/tabs
_PREFIX_RE = re.compile(
    r'^([\s│|]*)'                   # leading whitespace / pipe characters
    r'(?:[├└╠╚](?:─+|──+)\s*'      # Unicode box chars
    r'|[|+`\\*\-]+[-─ ]+\s*'        # ASCII variants
    r'|\s*)'                         # or plain indentation
    r'(.+)$'
)

# Matches trailing comments like "(pour les pièces d'identité)"
_COMMENT_RE = re.compile(r'\s*\(.*?\)\s*$')

# Characters per indentation level — detected automatically
_INDENT_SIZE = None


def strip_comment(name: str) -> str:
    """Remove inline parenthetical comments from entry names."""
    return _COMMENT_RE.sub('', name).strip()


def detect_indent_unit(lines: list[str]) -> int:
    """
    Auto-detect the number of leading characters that represent one indent
    level by looking at the minimum non-zero indent delta across all lines.
    """
    depths = []
    for line in lines:
        m = _PREFIX_RE.match(line)
        if m:
            depths.append(len(m.group(1)))
    deltas = sorted({b - a for a, b in zip(depths, depths[1:]) if b > a})
    return deltas[0] if deltas else 4


def parse_structure(raw: str) -> list[tuple[int, str, bool]]:
    """
    Parse raw tree text into a list of (depth, name, is_dir) tuples.

    Returns an empty list if no valid entries are found.
    """
    lines = [l.rstrip() for l in raw.splitlines() if l.strip()]

    # Skip empty / pure separator lines
    lines = [l for l in lines if not re.match(r'^[\s─│├└╠╚|+\-=]+$', l)]

    if not lines:
        return []

    indent_unit = detect_indent_unit(lines)

    entries = []
    for line in lines:
        m = _PREFIX_RE.match(line)
        if not m:
            continue

        prefix, name = m.group(1), m.group(2).strip()
        name = strip_comment(name)

        # Skip blank names or pure decoration
        if not name or re.match(r'^[\-─=]+$', name):
            continue

        depth = len(prefix) // max(indent_unit, 1)

        # Is it a directory?
        # A name ending with / is always a dir.
        # A name with no extension and no dot is treated as a dir if it
        # appears in the source with a trailing slash — otherwise it is a file.
        is_dir = name.endswith('/')
        if is_dir:
            name = name.rstrip('/')

        entries.append((depth, name, is_dir))

    return entries


# ─── Tree Builder ──────────────────────────────────────────

def build_paths(entries: list[tuple[int, str, bool]]) -> list[tuple[Path, bool]]:
    """
    Convert (depth, name, is_dir) tuples into (relative_path, is_dir) pairs.
    """
    stack: list[str] = []   # current directory chain
    result: list[tuple[Path, bool]] = []

    for depth, name, is_dir in entries:
        # Trim stack to current depth
        stack = stack[:depth]

        current = Path(*stack, name) if stack else Path(name)

        result.append((current, is_dir))

        if is_dir:
            stack.append(name)

    return result


# ─── Creator ───────────────────────────────────────────────

def create_structure(
    paths: list[tuple[Path, bool]],
    root: Path,
    dry_run: bool = False,
) -> tuple[int, int, list[str]]:
    """
    Create directories and files under *root*.

    Returns (dirs_created, files_created, errors).
    """
    dirs_created = 0
    files_created = 0
    errors: list[str] = []

    for rel_path, is_dir in paths:
        full = root / rel_path
        try:
            if is_dir:
                if not dry_run:
                    full.mkdir(parents=True, exist_ok=True)
                dirs_created += 1
                icon = f"{C.CYAN}📁{C.RESET}"
                label = f"{C.CYAN}{rel_path}/{C.RESET}"
                tag   = f"{C.DIM}(dir){C.RESET}"
            else:
                if not dry_run:
                    full.parent.mkdir(parents=True, exist_ok=True)
                    if not full.exists():
                        full.touch()
                files_created += 1
                icon = f"{C.GREEN}📄{C.RESET}"
                label = f"{C.GREEN}{rel_path}{C.RESET}"
                tag   = f"{C.DIM}(file){C.RESET}"

            prefix = f"{C.YELLOW}[DRY-RUN]{C.RESET} " if dry_run else f"{C.GREEN}✔{C.RESET}  "
            print(f"  {prefix}{icon}  {label} {tag}")

        except OSError as e:
            errors.append(f"{rel_path}: {e}")
            print(f"  {C.RED}✘{C.RESET}  {C.RED}{rel_path}{C.RESET}  — {e}")

    return dirs_created, files_created, errors


# ─── Interactive Input ─────────────────────────────────────

PASTE_PROMPT = f"""
{C.CYAN}{C.BOLD}Paste your folder structure below.{C.RESET}
{C.DIM}(When you're done, press Enter twice — or type END on its own line){C.RESET}

"""

def read_multiline_input() -> str:
    """Read multi-line paste from stdin until two blank lines or 'END'."""
    print(PASTE_PROMPT, end='')
    lines = []
    blank_count = 0
    try:
        while True:
            line = input()
            if line.strip().upper() == 'END':
                break
            if line.strip() == '':
                blank_count += 1
                if blank_count >= 2:
                    break
                lines.append(line)
            else:
                blank_count = 0
                lines.append(line)
    except EOFError:
        pass
    return '\n'.join(lines)


# ─── Preview Renderer ──────────────────────────────────────

def print_preview(paths: list[tuple[Path, bool]]) -> None:
    """Print a visual tree of what will be created."""
    print(f"\n{C.BOLD}Structure preview:{C.RESET}")
    for rel_path, is_dir in paths:
        parts = rel_path.parts
        indent = "  " + "  " * (len(parts) - 1)
        name = parts[-1]
        if is_dir:
            print(f"{indent}{C.CYAN}📁 {name}/{C.RESET}")
        else:
            print(f"{indent}{C.GREEN}📄 {name}{C.RESET}")


# ─── Main ──────────────────────────────────────────────────

def main():
    print(BANNER)

    parser = argparse.ArgumentParser(
        prog='ophelia',
        description='Paste a folder structure — Ophelia creates it.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument('-i', '--input',   help='Path to a text file containing the structure')
    parser.add_argument('-o', '--output',  help='Root directory to create the structure in (default: current dir)')
    parser.add_argument('--preview',       action='store_true', help='Preview only — do not create any files')
    parser.add_argument('--no-color',      action='store_true', help='Disable colored output')
    args = parser.parse_args()

    if args.no_color:
        no_color()

    # ── Read raw structure ──────────────────────────────────
    if args.input:
        input_path = Path(args.input)
        if not input_path.exists():
            print(f"{C.RED}Error:{C.RESET} File not found: {args.input}")
            sys.exit(1)
        raw = input_path.read_text(encoding='utf-8')
        print(f"{C.DIM}Reading structure from:{C.RESET} {args.input}\n")
    else:
        raw = read_multiline_input()

    if not raw.strip():
        print(f"\n{C.YELLOW}Nothing to do — empty input.{C.RESET}")
        sys.exit(0)

    # ── Parse ───────────────────────────────────────────────
    entries = parse_structure(raw)
    if not entries:
        print(f"\n{C.RED}Could not parse any entries from the input.{C.RESET}")
        print(f"{C.DIM}Make sure the structure uses standard tree notation (├──, |──, spaces, etc.){C.RESET}")
        sys.exit(1)

    paths = build_paths(entries)

    # ── Output root ─────────────────────────────────────────
    if args.output:
        root = Path(args.output)
    else:
        # Use the first top-level directory name as the root, in cwd
        root = Path.cwd()

    # ── Preview ─────────────────────────────────────────────
    print_preview(paths)
    print()

    if args.preview:
        print(f"{C.YELLOW}[DRY-RUN MODE]{C.RESET} No files or directories will be created.\n")

    # ── Confirm ─────────────────────────────────────────────
    total = len(paths)
    dirs  = sum(1 for _, d in paths if d)
    files = total - dirs
    root_display = root if args.output else Path.cwd()

    print(f"{C.BOLD}Summary:{C.RESET} {dirs} director{'ies' if dirs != 1 else 'y'}, "
          f"{files} file{'s' if files != 1 else ''}")
    print(f"{C.BOLD}Root:{C.RESET}    {root_display}\n")

    if not args.preview:
        try:
            confirm = input(f"{C.BOLD}Create structure? [Y/n]{C.RESET} ").strip().lower()
        except EOFError:
            confirm = 'y'

        if confirm not in ('', 'y', 'yes'):
            print(f"\n{C.YELLOW}Aborted.{C.RESET}")
            sys.exit(0)

        print()
        root.mkdir(parents=True, exist_ok=True)
        dirs_made, files_made, errors = create_structure(paths, root, dry_run=False)

        print(f"\n{C.GREEN}{C.BOLD}Done!{C.RESET}  "
              f"{dirs_made} director{'ies' if dirs_made != 1 else 'y'} + "
              f"{files_made} file{'s' if files_made != 1 else ''} created "
              f"in {C.CYAN}{root_display}{C.RESET}")

        if errors:
            print(f"\n{C.RED}Errors ({len(errors)}):{C.RESET}")
            for e in errors:
                print(f"  • {e}")
    else:
        create_structure(paths, root, dry_run=True)
        print(f"\n{C.YELLOW}Dry-run complete.{C.RESET} Run without --preview to create the structure.")


if __name__ == '__main__':
    main()
