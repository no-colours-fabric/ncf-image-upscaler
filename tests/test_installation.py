import os
import subprocess

import pytest

from ncf_image_upscaler.installation import PATH_MARKER, install_command


def launcher_at(tmp_path):
    project = tmp_path / "project with spaces"
    project.mkdir()
    launcher = project / "ncf-upscale"
    launcher.write_text('#!/bin/sh\nprintf "test-upscaler:%s\\n" "$1"\n')
    launcher.chmod(0o755)
    return project


def test_installed_command_runs_from_another_directory_and_reinstalls_safely(tmp_path):
    project = launcher_at(tmp_path)
    bin_dir = tmp_path / "bin"
    profile = tmp_path / "profile"
    for _ in range(2):
        result = install_command(
            project, bin_dir=bin_dir, search_path=str(bin_dir), profile=profile
        )
        assert not result.needs_new_shell
    assert not profile.exists()
    assert result.command.is_symlink()
    output = subprocess.check_output(
        ["ncf-upscale", "image with spaces.png"],
        cwd=tmp_path,
        env={**os.environ, "PATH": str(bin_dir)},
        text=True,
    )
    assert output == "test-upscaler:image with spaces.png\n"


def test_path_setup_preserves_profile_is_idempotent_and_handles_spaces(tmp_path):
    project = launcher_at(tmp_path)
    bin_dir = tmp_path / "user's bin"
    profile = tmp_path / "profile"
    original = "# existing custom settings\nexport EXISTING_SETTING=kept"
    profile.write_text(original)
    for _ in range(2):
        result = install_command(
            project, bin_dir=bin_dir, search_path="/usr/bin:/bin", profile=profile
        )
        assert result.needs_new_shell
    content = profile.read_text()
    assert content.startswith(original + "\n")
    assert content.count(PATH_MARKER) == 1
    # Execute the generated profile as a fresh shell would, with no PATH
    # inherited from the installer and from a different working directory.
    output = subprocess.check_output(
        ["/bin/zsh", "-fc", 'source "$1"; ncf-upscale check', "zsh", str(profile)],
        env={**os.environ, "PATH": "/usr/bin:/bin"},
        cwd=tmp_path,
        text=True,
    )
    assert output == "test-upscaler:check\n"


@pytest.mark.parametrize("kind", ["file", "symlink", "dangling"])
def test_unrelated_command_is_never_replaced(tmp_path, kind):
    project = launcher_at(tmp_path)
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    command = bin_dir / "ncf-upscale"
    if kind == "file":
        command.write_text("another application")
    elif kind == "symlink":
        target = tmp_path / "other"
        target.write_text("another application")
        command.symlink_to(target)
    else:
        command.symlink_to(tmp_path / "absent")
    before = command.readlink() if command.is_symlink() else command.read_bytes()
    with pytest.raises(FileExistsError, match="already in use"):
        install_command(project, bin_dir=bin_dir, search_path=str(bin_dir))
    after = command.readlink() if command.is_symlink() else command.read_bytes()
    assert after == before


def test_installed_entry_point_survives_removing_source_folder(tmp_path):
    import shutil

    project = launcher_at(tmp_path)
    installed = tmp_path / "Application Support" / "runtime" / "env" / "bin" / "ncf-upscale"
    installed.parent.mkdir(parents=True)
    installed.write_bytes((project / "ncf-upscale").read_bytes())
    installed.chmod(0o755)
    runtime_link = tmp_path / "runtime link"
    runtime_link.symlink_to(installed.parent, target_is_directory=True)
    bin_dir = tmp_path / "bin"
    for _ in range(2):
        result = install_command(
            project,
            launcher=runtime_link / "ncf-upscale",
            bin_dir=bin_dir,
            search_path=str(bin_dir),
        )
    shutil.rmtree(project)
    output = subprocess.check_output([str(result.command), "after removal"], text=True)
    assert output == "test-upscaler:after removal\n"


def test_source_based_command_upgrades_to_installed_entry_point(tmp_path):
    project = launcher_at(tmp_path)
    bin_dir = tmp_path / "bin"
    profile = tmp_path / "profile"
    old = install_command(project, bin_dir=bin_dir, search_path=str(bin_dir), profile=profile)
    installed = tmp_path / "installed-ncf-upscale"
    installed.write_bytes((project / "ncf-upscale").read_bytes())
    installed.chmod(0o755)
    result = install_command(
        project, launcher=installed, bin_dir=bin_dir, search_path=str(bin_dir), profile=profile
    )
    assert result.command == old.command
    assert result.command.resolve() == installed
    assert not profile.exists()
