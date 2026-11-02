#!/usr/bin/env python3
"""Update image.repository and image.tag in the production Helm values."""

import argparse
import os
import re
import tempfile
from pathlib import Path

ECR_PATTERN = re.compile(
    r"^\d{12}\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com/[a-z0-9][a-z0-9._/-]*$"
)
SHA_PATTERN = re.compile(r"^[0-9a-f]{40}$")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("repository")
    parser.add_argument("tag")
    parser.add_argument(
        "--file", default="gitops-demo/helm-values/prod/values.yaml"
    )
    args = parser.parse_args()

    if not ECR_PATTERN.fullmatch(args.repository):
        raise ValueError(f"Invalid ECR repository: {args.repository}")
    if not SHA_PATTERN.fullmatch(args.tag):
        raise ValueError("Tag must be a full lowercase Git SHA")

    path = Path(args.file)
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    output = []
    in_image = False
    updated = set()

    for line in lines:
        if line.startswith("image:"):
            in_image = True
        elif in_image and line and not line[0].isspace():
            in_image = False

        newline = "\n" if line.endswith("\n") else ""
        if in_image and re.match(r"^  repository:", line):
            output.append(f"  repository: {args.repository}{newline}")
            updated.add("repository")
        elif in_image and re.match(r"^  tag:", line):
            output.append(f'  tag: "{args.tag}"{newline}')
            updated.add("tag")
        else:
            output.append(line)

    if updated != {"repository", "tag"}:
        raise ValueError("image.repository or image.tag was not found")

    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=path.parent, delete=False
    ) as temporary:
        temporary.writelines(output)
        temporary_path = Path(temporary.name)
    os.replace(temporary_path, path)


if __name__ == "__main__":
    main()
