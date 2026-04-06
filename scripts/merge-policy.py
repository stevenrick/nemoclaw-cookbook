#!/usr/bin/env python3
"""Merge policy fragments into the upstream OpenClaw sandbox policy YAML.

Works with the raw text to preserve upstream formatting and comments.
Reads structured fragment files that specify:
  - add_endpoints: {section: [endpoint entries]}
  - add_binaries:  {section: [binary entries]}
  - new_sections:  {section_key: {full section definition}}

Usage:
    merge-policy.py <policy-file> <fragment1.yaml> [fragment2.yaml ...]

Modifies <policy-file> in place.
"""
import re
import sys


def parse_fragment(path):
    """Parse a fragment YAML file into add_endpoints, add_binaries, new_sections."""
    import yaml  # lazy import — only needed for fragments, not the policy file
    with open(path) as f:
        data = yaml.safe_load(f)
    return (
        data.get("add_endpoints", {}),
        data.get("add_binaries", {}),
        data.get("new_sections", {}),
    )


def find_section_range(lines, section_key):
    """Find the line range for a top-level network_policies section.

    Returns (start, end) where start is the '  section_key:' line
    and end is the line AFTER the last line of that section.
    """
    pattern = re.compile(rf"^  {re.escape(section_key)}:\s*$")
    start = None
    for i, line in enumerate(lines):
        if pattern.match(line):
            start = i
            break
    if start is None:
        return None, None

    # Find the end: next line at indentation level <= 2 (next section or end of file)
    end = start + 1
    while end < len(lines):
        line = lines[end]
        # Empty lines or comments between sections
        if line.strip() == "" or (line.strip().startswith("#") and not line.startswith("      ")):
            # Peek ahead — if next non-empty line is a new section, stop here
            peek = end + 1
            while peek < len(lines) and lines[peek].strip() == "":
                peek += 1
            if peek < len(lines) and re.match(r"^  \S", lines[peek]):
                break
            end += 1
            continue
        if re.match(r"^  \S", line) and end > start:
            break
        end += 1
    return start, end


def find_binaries_line(lines, section_start, section_end):
    """Find the '    binaries:' line within a section."""
    for i in range(section_start, section_end):
        if lines[i].strip() == "binaries:":
            return i
    return None


def find_last_endpoint(lines, section_start, binaries_line):
    """Find the last endpoint entry line before binaries."""
    last = section_start
    for i in range(section_start + 1, binaries_line):
        if lines[i].strip() and not lines[i].strip().startswith("#"):
            last = i
    return last


def find_last_binary(lines, binaries_line, section_end):
    """Find the last binary entry line in a section."""
    last = binaries_line
    for i in range(binaries_line + 1, section_end):
        if lines[i].strip().startswith("- {"):
            last = i
    return last


def format_endpoint_yaml(endpoint, indent=6):
    """Format an endpoint dict as YAML text lines."""
    prefix = " " * indent
    result = []
    if "access" in endpoint:
        result.append(f"{prefix}- host: {endpoint['host']}")
        result.append(f"{prefix}  port: {endpoint['port']}")
        result.append(f"{prefix}  access: {endpoint['access']}")
    else:
        result.append(f"{prefix}- host: {endpoint['host']}")
        result.append(f"{prefix}  port: {endpoint['port']}")
        if "protocol" in endpoint:
            result.append(f"{prefix}  protocol: {endpoint['protocol']}")
        if "enforcement" in endpoint:
            result.append(f"{prefix}  enforcement: {endpoint['enforcement']}")
        if "tls" in endpoint:
            result.append(f"{prefix}  tls: {endpoint['tls']}")
        if "rules" in endpoint:
            result.append(f"{prefix}  rules:")
            for rule in endpoint["rules"]:
                allow = rule["allow"]
                result.append(
                    f'{prefix}    - allow: {{ method: {allow["method"]}, path: "{allow["path"]}" }}'
                )
    return result


def format_binary_yaml(binary, indent=6):
    """Format a binary dict as a YAML line."""
    prefix = " " * indent
    return f"{prefix}- {{ path: {binary['path']} }}"


def format_new_section(key, section, indent=2):
    """Format a complete new policy section as YAML text lines."""
    prefix = " " * indent
    lines = []
    lines.append("")
    lines.append(f"{prefix}{key}:")
    lines.append(f"{prefix}  name: {section['name']}")
    lines.append(f"{prefix}  endpoints:")
    for ep in section.get("endpoints", []):
        lines.extend(format_endpoint_yaml(ep, indent=indent + 4))
    if "binaries" in section:
        lines.append(f"{prefix}  binaries:")
        for b in section["binaries"]:
            lines.append(format_binary_yaml(b, indent=indent + 4))
    return lines


def merge(policy_path, fragment_paths):
    with open(policy_path) as f:
        lines = f.read().splitlines()

    # Collect all additions from fragments
    all_endpoints = {}
    all_binaries = {}
    all_new_sections = {}

    for fpath in fragment_paths:
        endpoints, binaries, new_sections = parse_fragment(fpath)
        for section, eps in endpoints.items():
            all_endpoints.setdefault(section, []).extend(eps)
        for section, bins in binaries.items():
            all_binaries.setdefault(section, []).extend(bins)
        all_new_sections.update(new_sections)

    # Apply endpoint additions to existing sections
    # Process in reverse order so line numbers stay valid
    modifications = []

    for section_key, endpoints in all_endpoints.items():
        start, end = find_section_range(lines, section_key)
        if start is None:
            print(f"WARNING: section '{section_key}' not found in policy — skipping endpoints", file=sys.stderr)
            continue
        binaries_line = find_binaries_line(lines, start, end)
        if binaries_line is None:
            print(f"WARNING: no binaries line in section '{section_key}' — appending endpoints before section end", file=sys.stderr)
            insert_at = end
        else:
            insert_at = binaries_line
        new_lines = []
        for ep in endpoints:
            new_lines.extend(format_endpoint_yaml(ep))
        modifications.append((insert_at, new_lines))

    # Apply binary additions to existing sections
    for section_key, binaries in all_binaries.items():
        start, end = find_section_range(lines, section_key)
        if start is None:
            print(f"WARNING: section '{section_key}' not found in policy — skipping binaries", file=sys.stderr)
            continue
        # Re-find after potential modifications — we'll sort and apply in reverse
        binaries_line = find_binaries_line(lines, start, end)
        if binaries_line is None:
            print(f"WARNING: no binaries line in section '{section_key}' — skipping", file=sys.stderr)
            continue
        last_binary = find_last_binary(lines, binaries_line, end)
        insert_at = last_binary + 1
        new_lines = [format_binary_yaml(b) for b in binaries]
        modifications.append((insert_at, new_lines))

    # Sort modifications by line number descending so insertions don't shift later ones
    modifications.sort(key=lambda x: x[0], reverse=True)
    for insert_at, new_lines in modifications:
        for i, new_line in enumerate(new_lines):
            lines.insert(insert_at + i, new_line)

    # Add new sections — insert before 'nvidia:' section (or at end of network_policies)
    if all_new_sections:
        # Find insertion point: before nvidia section
        nvidia_start, _ = find_section_range(lines, "nvidia")
        if nvidia_start is not None:
            insert_at = nvidia_start
        else:
            # Fallback: end of file
            insert_at = len(lines)

        new_section_lines = []
        for key, section in all_new_sections.items():
            # Check section doesn't already exist
            existing_start, _ = find_section_range(lines, key)
            if existing_start is not None:
                print(f"INFO: section '{key}' already exists in upstream — skipping (upstream handles it)", file=sys.stderr)
                continue
            new_section_lines.extend(format_new_section(key, section))

        for i, line in enumerate(new_section_lines):
            lines.insert(insert_at + i, line)

    # Write result
    with open(policy_path, "w") as f:
        f.write("\n".join(lines) + "\n")

    print(f"Policy merged: {len(fragment_paths)} fragment(s) applied", file=sys.stderr)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <policy-file> <fragment1.yaml> [fragment2.yaml ...]", file=sys.stderr)
        sys.exit(1)
    merge(sys.argv[1], sys.argv[2:])
