#!/usr/bin/env python3
"""Export the working sources without Git history, ignored data or local ownership."""

import subprocess
import tarfile
from pathlib import Path


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    paths = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=root
    ).decode().split("\0")
    output = root / "dist" / "CodexUsage-source.tar.gz"
    output.parent.mkdir(parents=True, exist_ok=True)

    def clean_metadata(info: tarfile.TarInfo) -> tarfile.TarInfo:
        info.uid = info.gid = 0
        info.uname = info.gname = ""
        return info

    with tarfile.open(output, "w:gz", format=tarfile.PAX_FORMAT) as archive:
        for name in sorted(set(paths)):
            path = root / name
            if not name or not path.is_file() or path.is_symlink():
                continue
            if any(part.startswith("._") or part == ".DS_Store" for part in path.parts):
                continue
            archive.add(path, arcname=f"CodexUsage/{name}", recursive=False, filter=clean_metadata)
    print(output)


if __name__ == "__main__":
    main()
