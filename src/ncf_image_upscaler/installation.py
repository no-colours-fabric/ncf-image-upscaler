"""Register the CLI in the user's PATH without replacing unrelated commands."""

import argparse
import os
import shlex
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

PATH_MARKER = "# >>> ncf-image-upscaler PATH >>>"


@dataclass(frozen=True)
class CommandInstallation:
    command: Path
    needs_new_shell: bool


def install_command(
    project_dir: Path,
    *,
    launcher: Path | None = None,
    bin_dir: Path | None = None,
    search_path: str | None = None,
    profile: Path | None = None,
) -> CommandInstallation:
    source_launcher = project_dir.resolve() / "ncf-upscale"
    launcher = launcher.absolute() if launcher is not None else source_launcher
    if not launcher.is_file() or not os.access(launcher, os.X_OK):
        raise FileNotFoundError(f"Executable not found: {launcher}")
    bin_dir = bin_dir if bin_dir is not None else Path.home() / ".local" / "bin"
    search_path = search_path if search_path is not None else os.environ.get("PATH", "")
    command = bin_dir / "ncf-upscale"
    # lexists-style check also protects dangling symlinks and other projects.
    if command.is_symlink():
        if command.resolve() != launcher.resolve():
            # Upgrade our previous source-based installation, but never replace
            # another project's command (including a dangling symlink).
            if command.resolve() == source_launcher and source_launcher.is_file():
                with tempfile.TemporaryDirectory(
                    prefix=".ncf-upscale-install-", dir=bin_dir
                ) as temporary:
                    replacement = Path(temporary) / "ncf-upscale"
                    replacement.symlink_to(launcher)
                    replacement.replace(command)
            else:
                raise FileExistsError(
                    f"Command name already in use: {command}. "
                    "The existing symlink was preserved; free this name before installing."
                )
    elif command.exists():
        raise FileExistsError(
            f"Command name already in use: {command}. "
            "The existing file was preserved; free this name before installing."
        )
    else:
        bin_dir.mkdir(parents=True, exist_ok=True)
        command.symlink_to(launcher)

    needs_new_shell = str(bin_dir) not in search_path.split(os.pathsep)
    if needs_new_shell:
        if profile is None:
            if Path(os.environ.get("SHELL", "/bin/zsh")).name == "bash":
                profile = Path.home() / ".bash_profile"
            else:
                profile = Path(os.environ.get("ZDOTDIR") or Path.home()) / ".zprofile"
        previous = profile.read_text() if profile.exists() else ""
        if PATH_MARKER not in previous:
            quoted_bin = shlex.quote(str(bin_dir))
            block = (
                f"{PATH_MARKER}\n"
                'case ":$PATH:" in\n'
                f"    *:{quoted_bin}:*) ;;\n"
                f'    *) export PATH={quoted_bin}:"$PATH" ;;\n'
                "esac\n"
                "# <<< ncf-image-upscaler PATH <<<\n"
            )
            profile.parent.mkdir(parents=True, exist_ok=True)
            with profile.open("a") as stream:
                if previous and not previous.endswith("\n"):
                    stream.write("\n")
                stream.write("\n" + block)
    return CommandInstallation(command, needs_new_shell)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Install the ncf-upscale command for the current user"
    )
    parser.add_argument("project_dir", type=Path)
    parser.add_argument(
        "--installed", action="store_true", help="use the installed Python entry point"
    )
    args = parser.parse_args()
    try:
        launcher = Path(sys.executable).parent / "ncf-upscale" if args.installed else None
        result = install_command(args.project_dir, launcher=launcher)
    except OSError as error:
        print(f"Command installation failed: {error}", file=sys.stderr)
        return 1
    print(f"Command installed: {result.command}")
    if result.needs_new_shell:
        print("Open a new terminal to use ncf-upscale from any folder.")
        print(
            "For the current terminal: export "
            f'PATH={shlex.quote(str(result.command.parent))}:"$PATH"'
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
