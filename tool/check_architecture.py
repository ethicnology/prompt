#!/usr/bin/env python3
"""Check feature and presentation-layer import boundaries."""

from pathlib import Path
import re
import sys


IMPORT = re.compile(r"^\s*import\s+['\"]([^'\"]+)['\"]")
PRESENTATION_FORBIDDEN = (
    "dart:io",
    "package:http/",
    "package:drift/",
)


def feature_for(path: str) -> str | None:
    parts = Path(path).parts
    try:
        return parts[parts.index("features") + 1]
    except (ValueError, IndexError):
        return None


def imported_feature(source: Path, import_path: str) -> str | None:
    match = re.search(r"(?:^|/)features/([^/]+)(?:/|$)", import_path)
    if match:
        return match.group(1)
    if not import_path.startswith("."):
        return None
    resolved = (source.parent / import_path).resolve()
    return feature_for(str(resolved))


def main() -> int:
    violations: list[str] = []
    for source in sorted(Path("lib/features").glob("**/*.dart")):
        source_feature = feature_for(str(source))
        is_presentation = "presentation" in source.parts
        for line_number, line in enumerate(source.read_text().splitlines(), 1):
            match = IMPORT.match(line)
            if not match:
                continue
            import_path = match.group(1)
            target_feature = imported_feature(source, import_path)
            if target_feature and target_feature != source_feature:
                if "/data/" in import_path or "/domain/" in import_path or "/presentation/" in import_path:
                    violations.append(
                        f"{source}:{line_number}: cross-feature internal import {import_path}"
                    )
            if is_presentation and (
                any(fragment in import_path for fragment in PRESENTATION_FORBIDDEN)
                or (
                    import_path.endswith("_service.dart")
                    and "/data/" in import_path
                )
            ):
                violations.append(f"{source}:{line_number}: forbidden presentation import {import_path}")

    if violations:
        print("Architecture violations detected:")
        print("\n".join(violations))
        return 1
    print("Architecture import boundaries passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
