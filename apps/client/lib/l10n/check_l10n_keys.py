#!/usr/bin/env python3
"""
Validate the custom Flutter l10n contract.

Rules enforced:
- l10n keys are stable English snake_case identifiers.
- keys must not contain Chinese directly or encoded as Unicode/hex fragments.
- keys must not repeat within a locale map.
- every supported locale map exposes the same key set.
- literal l10n.get()/l10n.getp() calls reference existing keys.
- template placeholders, such as {count}, stay consistent across locales.
- common UI-visible Chinese literals are not hardcoded in widgets/config objects.
"""

from __future__ import annotations

import os
import re
import sys
from collections import Counter
from dataclasses import dataclass

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
L10N_FILE = os.path.join(PROJECT_DIR, "l10n", "l10n.dart")
L10N_PART_FILES = (
    os.path.join(PROJECT_DIR, "l10n", "l10n_zh.dart"),
    os.path.join(PROJECT_DIR, "l10n", "l10n_en.dart"),
)
L10N_SOURCE_FILES = {os.path.realpath(L10N_FILE), *(os.path.realpath(path) for path in L10N_PART_FILES)}
CLIENT_DIR = PROJECT_DIR

DEFAULT_LOCALE = "_zh"
LOCALE_MAPS = ("_zh", "_en")
KEY_PATTERN = re.compile(r"^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$")
ENTRY_KEY_PATTERN = re.compile(r"^\s+'([^']+)'\s*:")
SINGLE_LINE_ENTRY_PATTERN = re.compile(r"^\s+'([^']+)'\s*:\s*'((?:[^'\\]|\\.)*)'\s*,?\s*$")
VALUE_LINE_PATTERN = re.compile(r"^\s*'((?:[^'\\]|\\.)*)'\s*,?\s*$")
CONSUMER_KEY_PATTERN = re.compile(r"l10n\.(?:get|getp)\('([^']+)'")
PLACEHOLDER_PATTERN = re.compile(r"\{([a-zA-Z][a-zA-Z0-9_]*)\}")
CHINESE_TEXT_PATTERN = r"[^'\"\n]*[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff][^'\"\n]*"
HARDCODED_UI_PATTERNS = (
    ("Text literal", re.compile(rf"\bText\(\s*(?:const\s*)?['\"]({CHINESE_TEXT_PATTERN})['\"]")),
    ("SnackBar Text literal", re.compile(rf"\bSnackBar\(\s*content:\s*Text\(\s*['\"]({CHINESE_TEXT_PATTERN})['\"]")),
    ("labelText literal", re.compile(rf"\blabelText:\s*['\"]({CHINESE_TEXT_PATTERN})['\"]")),
    ("hintText literal", re.compile(rf"\bhintText:\s*['\"]({CHINESE_TEXT_PATTERN})['\"]")),
    ("helperText literal", re.compile(rf"\bhelperText:\s*['\"]({CHINESE_TEXT_PATTERN})['\"]")),
    ("errorText literal", re.compile(rf"\berrorText:\s*['\"]({CHINESE_TEXT_PATTERN})['\"]")),
    ("tooltip literal", re.compile(rf"\btooltip:\s*['\"]({CHINESE_TEXT_PATTERN})['\"]")),
    ("semanticsLabel literal", re.compile(rf"\bsemanticsLabel:\s*['\"]({CHINESE_TEXT_PATTERN})['\"]")),
)
HARDCODED_KEY_CONFIG_PATTERN = re.compile(
    rf"\b(?:titleKey|subtitleKey|descKey|descriptionKey|nameKey|labelKey|phaseKey)\s*:\s*['\"]({CHINESE_TEXT_PATTERN})['\"]"
)
LABEL_METHOD_PATTERN = re.compile(
    r"\bString\s+(?:get\s+)?[A-Za-z0-9_]*(?:label|title|name|description|frequency)[A-Za-z0-9_]*\b",
    re.IGNORECASE,
)
RETURN_CHINESE_LITERAL_PATTERN = re.compile(rf"\breturn\s+['\"]({CHINESE_TEXT_PATTERN})['\"]")


@dataclass(frozen=True)
class Entry:
    key: str
    value: str
    line: int


def _has_hex_chinese(key: str) -> tuple[bool, str]:
    for part in key.split("_"):
        cleaned = part.replace("{", "").replace("}", "")
        if len(cleaned) < 4 or not all(c in "0123456789abcdef" for c in cleaned.lower()):
            continue
        try:
            codepoint = int(cleaned, 16)
        except (ValueError, OverflowError):
            continue
        if 0x3400 <= codepoint <= 0x9FFF or 0xF900 <= codepoint <= 0xFAFF:
            return True, f'hex codepoint {cleaned} = "{chr(codepoint)}"'
    return False, ""


def _has_direct_chinese(text: str) -> tuple[bool, str]:
    for ch in text:
        codepoint = ord(ch)
        if 0x3400 <= codepoint <= 0x4DBF or 0x4E00 <= codepoint <= 0x9FFF or 0xF900 <= codepoint <= 0xFAFF:
            return True, f'character "{ch}"'
    return False, ""


def _section_lines(content: str, map_name: str) -> tuple[int, list[str]]:
    markers = (
        f"  static const {map_name} = {{",
        f"const {map_name} = <String, String>{{",
        f"const {map_name} = {{",
    )
    marker = next((candidate for candidate in markers if candidate in content), "")
    start = content.find(marker)
    if start < 0:
        raise ValueError(f"Cannot find locale map {map_name}")
    line_start = content[:start].count("\n") + 1
    end = content.find("\n};", start)
    indented_end = content.find("\n  };", start)
    if indented_end >= 0 and (end < 0 or indented_end < end):
        end = indented_end
    if end < 0:
        raise ValueError(f"Cannot find end of locale map {map_name}")
    return line_start, content[start:end].splitlines()


def _parse_locale_entries(content: str, map_name: str) -> list[Entry]:
    base_line, lines = _section_lines(content, map_name)
    entries: list[Entry] = []
    for offset, line in enumerate(lines, start=0):
        key_match = ENTRY_KEY_PATTERN.match(line)
        if not key_match:
            continue

        key = key_match.group(1)
        value = ""
        single_line_match = SINGLE_LINE_ENTRY_PATTERN.match(line)
        if single_line_match:
            value = single_line_match.group(2)
        else:
            for next_line in lines[offset + 1 :]:
                value_match = VALUE_LINE_PATTERN.match(next_line)
                if value_match:
                    value = value_match.group(1)
                    break
                if ENTRY_KEY_PATTERN.match(next_line):
                    break

        entries.append(Entry(key, value, base_line + offset))
    return entries


def _check_key_shape(key: str, location: str) -> list[str]:
    errors: list[str] = []
    if not KEY_PATTERN.fullmatch(key):
        errors.append(f"{location}: key must be English snake_case: {key}")
    has_direct, detail = _has_direct_chinese(key)
    if has_direct:
        errors.append(f"{location}: key contains direct Chinese {detail}: {key}")
    has_hex, detail = _has_hex_chinese(key)
    if has_hex:
        errors.append(f"{location}: key contains hex-encoded Chinese {detail}: {key}")
    return errors


def check_l10n_file(content: str) -> tuple[dict[str, dict[str, Entry]], list[str]]:
    locale_entries: dict[str, dict[str, Entry]] = {}
    errors: list[str] = []

    for map_name in LOCALE_MAPS:
        entries = _parse_locale_entries(content, map_name)
        counts = Counter(entry.key for entry in entries)
        for duplicate_key in sorted(key for key, count in counts.items() if count > 1):
            lines = [str(entry.line) for entry in entries if entry.key == duplicate_key]
            errors.append(f"{map_name}: duplicate key {duplicate_key} at lines {', '.join(lines)}")

        locale_entries[map_name] = {}
        for entry in entries:
            locale_entries[map_name].setdefault(entry.key, entry)
            errors.extend(_check_key_shape(entry.key, f"{map_name}:{entry.line}"))

    baseline_keys = set(locale_entries[DEFAULT_LOCALE])
    for map_name, entries in locale_entries.items():
        keys = set(entries)
        missing = sorted(baseline_keys - keys)
        extra = sorted(keys - baseline_keys)
        if missing:
            errors.append(f"{map_name}: missing {len(missing)} key(s) from {DEFAULT_LOCALE}: {', '.join(missing[:20])}")
        if extra:
            errors.append(f"{map_name}: has {len(extra)} key(s) not in {DEFAULT_LOCALE}: {', '.join(extra[:20])}")

    for key in sorted(baseline_keys):
        placeholder_sets = {
            map_name: set(PLACEHOLDER_PATTERN.findall(entries[key].value))
            for map_name, entries in locale_entries.items()
            if key in entries
        }
        if len({tuple(sorted(placeholders)) for placeholders in placeholder_sets.values()}) > 1:
            details = ", ".join(
                f"{map_name}={sorted(placeholders)}" for map_name, placeholders in placeholder_sets.items()
            )
            errors.append(f"{key}: placeholder mismatch across locales: {details}")

    return locale_entries, errors


def check_consumer_files(locale_entries: dict[str, dict[str, Entry]]) -> list[str]:
    errors: list[str] = []
    known_keys = set(locale_entries[DEFAULT_LOCALE])

    for root, dirs, files in os.walk(CLIENT_DIR):
        dirs[:] = [d for d in dirs if not d.startswith("_") and d not in [".dart_tool", "build", ".git"]]
        for filename in files:
            if not filename.endswith(".dart"):
                continue
            path = os.path.join(root, filename)
            if os.path.realpath(path) in L10N_SOURCE_FILES:
                continue

            with open(path, "r", encoding="utf-8") as file:
                file_content = file.read()

            rel = os.path.relpath(path, CLIENT_DIR)
            if "l10n.getp(l10n.get(" in file_content or "l10n.get(l10n.get(" in file_content:
                errors.append(f"{rel}: l10n key must be a literal English key, not another localized value")

            for match in CONSUMER_KEY_PATTERN.finditer(file_content):
                key = match.group(1)
                line = file_content.count("\n", 0, match.start()) + 1
                location = f"{rel}:{line}"
                errors.extend(_check_key_shape(key, location))
                if key not in known_keys:
                    errors.append(f"{location}: key is not defined in {DEFAULT_LOCALE}: {key}")

            errors.extend(check_hardcoded_ui_text(rel, file_content))

    return errors


def check_hardcoded_ui_text(rel: str, file_content: str) -> list[str]:
    errors: list[str] = []

    for label, pattern in HARDCODED_UI_PATTERNS:
        for match in pattern.finditer(file_content):
            line = file_content.count("\n", 0, match.start()) + 1
            text = match.group(1)
            errors.append(
                f"{rel}:{line}: hardcoded Chinese UI text in {label}: {text!r}; "
                "use l10n.get()/l10n.getp() with an English key"
            )

    for match in HARDCODED_KEY_CONFIG_PATTERN.finditer(file_content):
        line = file_content.count("\n", 0, match.start()) + 1
        text = match.group(1)
        errors.append(
            f"{rel}:{line}: localized key/config value must be an English key, not Chinese text: {text!r}"
        )

    recent_label_declaration_line = 0
    for line_number, line in enumerate(file_content.splitlines(), start=1):
        if LABEL_METHOD_PATTERN.search(line):
            recent_label_declaration_line = line_number
        match = RETURN_CHINESE_LITERAL_PATTERN.search(line)
        if match and 0 < line_number - recent_label_declaration_line <= 8:
            text = match.group(1)
            errors.append(
                f"{rel}:{line_number}: label-like getter returns hardcoded Chinese text: {text!r}; "
                "return an English key and translate in the UI"
            )

    return errors


def main() -> int:
    content_parts = []
    for path in (L10N_FILE, *L10N_PART_FILES):
        with open(path, "r", encoding="utf-8") as file:
            content_parts.append(file.read())
    content = "\n".join(content_parts)

    errors: list[str] = []
    locale_entries, l10n_errors = check_l10n_file(content)
    errors.extend(l10n_errors)
    errors.extend(check_consumer_files(locale_entries))

    if errors:
        print("l10n validation failed:")
        for error in errors:
            print(f"  FAIL: {error}")
        return 1

    total_keys = len(locale_entries[DEFAULT_LOCALE])
    locales = ", ".join(LOCALE_MAPS)
    print(f"l10n validation passed: {total_keys} keys across {locales}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
