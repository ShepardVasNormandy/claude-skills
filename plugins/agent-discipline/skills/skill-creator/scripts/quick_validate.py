#!/usr/bin/env python3
"""
Quick validation script for skills - minimal version, standard library only
"""

import sys
import re
from pathlib import Path

ALLOWED_PROPERTIES = {
    'name', 'description', 'license', 'allowed-tools', 'metadata',
    'argument-hint', 'disable-model-invocation', 'user-invocable',
    'when_to_use', 'model', 'disallowed-tools',
}

# references/, scripts/ or assets/ paths named in SKILL.md, standalone or after <skill-dir>/
BUNDLED_PATH = re.compile(
    r'(?:(?<=<skill-dir>/)|(?<![\w./<>-]))'
    r'((?:references|scripts|assets)/[A-Za-z0-9_.-][A-Za-z0-9_./-]*)'
)


def parse_frontmatter(text):
    """Parse top-level keys of flat YAML frontmatter. Nested values (lists, maps) are kept as None."""
    frontmatter = {}
    key = None
    block_lines = None
    for line in text.split('\n'):
        top = re.match(r'^([A-Za-z_][A-Za-z0-9_-]*):(?:\s+(.*))?$', line)
        if top:
            key, value = top.group(1), (top.group(2) or '').strip()
            if key in frontmatter:
                raise ValueError(f"Duplicate key '{key}'")
            if value in ('|', '>', '|-', '>-'):
                block_lines = []
                frontmatter[key] = ''
            else:
                block_lines = None
                if len(value) >= 2 and value[0] == value[-1] and value[0] in '"\'':
                    value = value[1:-1]
                frontmatter[key] = value if value else None
        elif line.strip() == '' or line.startswith((' ', '\t')):
            if key is None:
                continue
            if block_lines is not None:
                block_lines.append(line.strip())
                frontmatter[key] = ' '.join(l for l in block_lines if l)
        else:
            raise ValueError(f"Unparseable frontmatter line: {line!r}")
    return frontmatter


def validate_skill(skill_path):
    """Basic validation of a skill"""
    skill_path = Path(skill_path)

    # Check SKILL.md exists
    skill_md = skill_path / 'SKILL.md'
    if not skill_md.exists():
        return False, "SKILL.md not found"

    # Read and validate frontmatter
    content = skill_md.read_text()
    if not content.startswith('---'):
        return False, "No YAML frontmatter found"

    # Extract frontmatter
    match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
    if not match:
        return False, "Invalid frontmatter format"

    try:
        frontmatter = parse_frontmatter(match.group(1))
    except ValueError as e:
        return False, f"Invalid frontmatter: {e}"

    # Check for unexpected properties
    unexpected_keys = set(frontmatter.keys()) - ALLOWED_PROPERTIES
    if unexpected_keys:
        return False, (
            f"Unexpected key(s) in SKILL.md frontmatter: {', '.join(sorted(unexpected_keys))}. "
            f"Allowed properties are: {', '.join(sorted(ALLOWED_PROPERTIES))}"
        )

    # Check required fields
    if 'name' not in frontmatter:
        return False, "Missing 'name' in frontmatter"
    if 'description' not in frontmatter:
        return False, "Missing 'description' in frontmatter"

    # Validate name
    name = frontmatter['name']
    if not isinstance(name, str) or not name.strip():
        return False, "Name must be a non-empty string"
    name = name.strip()
    # Check naming convention (hyphen-case: lowercase with hyphens)
    if not re.match(r'^[a-z0-9-]+$', name):
        return False, f"Name '{name}' should be hyphen-case (lowercase letters, digits, and hyphens only)"
    if name.startswith('-') or name.endswith('-') or '--' in name:
        return False, f"Name '{name}' cannot start/end with hyphen or contain consecutive hyphens"
    # Check name length (max 64 characters per spec)
    if len(name) > 64:
        return False, f"Name is too long ({len(name)} characters). Maximum is 64 characters."
    # Check name matches directory name
    if name != skill_path.resolve().name:
        return False, f"Name '{name}' does not match directory name '{skill_path.resolve().name}'"

    # Validate description
    description = frontmatter['description']
    if not isinstance(description, str) or not description.strip():
        return False, "Description must be a non-empty string"
    description = description.strip()
    # Check description length (max 1024 characters per spec)
    if len(description) > 1024:
        return False, f"Description is too long ({len(description)} characters). Maximum is 1024 characters."

    # Check every bundled path named in SKILL.md exists. scripts/ and assets/ are also common
    # repo-relative paths, so check those only when the skill ships that directory.
    body = content[match.end():]
    paths = {p.rstrip('.') for p in BUNDLED_PATH.findall(body)}
    missing = sorted(
        p for p in paths
        if (p.startswith('references/') or (skill_path / p.split('/')[0]).is_dir())
        and not (skill_path / p).exists()
    )
    if missing:
        return False, f"Path(s) named in SKILL.md do not exist: {', '.join(missing)}"

    return True, "Skill is valid!"


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python quick_validate.py <skill_directory>")
        sys.exit(1)

    valid, message = validate_skill(sys.argv[1])
    print(message)
    sys.exit(0 if valid else 1)
