"""SSH signatures (`ssh-keygen -Y`) for the store snapshot and the provider registry.

ed25519 keys; a namespace per purpose (opc_spec.vocab) so a signature cannot be replayed for another
use. Verification needs an allowed_signers file (principal + key), as the CLI does offline.
"""

from __future__ import annotations

import shutil
import subprocess
from typing import TYPE_CHECKING, Final

if TYPE_CHECKING:
    from pathlib import Path

PRINCIPAL: Final = "omarchy-plugin-check"


class SshSigError(Exception):
    """ssh-keygen is missing or a sign/verify call failed."""


def _ssh_keygen() -> str:
    exe = shutil.which("ssh-keygen")
    if exe is None:
        raise SshSigError("ssh-keygen not found")
    return exe


def keygen(path: Path, comment: str) -> None:
    """Create an unencrypted ed25519 key pair at `path` (+ .pub), private key mode 0600."""
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    run = subprocess.run(
        [_ssh_keygen(), "-q", "-t", "ed25519", "-N", "", "-C", comment, "-f", str(path)],
        capture_output=True,
        text=True,
        check=False,
    )
    if run.returncode != 0:
        raise SshSigError(run.stderr.strip())
    path.chmod(0o600)


def sign(data_path: Path, key_path: Path, namespace: str) -> Path:
    """Write `<data_path>.sig` (detached SSH signature) and return its path."""
    sig = data_path.with_name(data_path.name + ".sig")
    sig.unlink(missing_ok=True)
    run = subprocess.run(
        [_ssh_keygen(), "-q", "-Y", "sign", "-f", str(key_path), "-n", namespace, str(data_path)],
        capture_output=True,
        text=True,
        check=False,
    )
    if run.returncode != 0 or not sig.is_file():
        raise SshSigError(run.stderr.strip() or "ssh-keygen -Y sign produced no signature")
    return sig


def verify(
    data: bytes, sig_path: Path, allowed_signers: Path, namespace: str, principal: str = PRINCIPAL
) -> bool:
    """True iff `sig_path` is a valid `namespace` signature over `data` by `principal`."""
    run = subprocess.run(
        [
            _ssh_keygen(),
            "-Y",
            "verify",
            "-f",
            str(allowed_signers),
            "-I",
            principal,
            "-n",
            namespace,
            "-s",
            str(sig_path),
        ],
        input=data,
        capture_output=True,
        check=False,
    )
    return run.returncode == 0


def allowed_signers_line(pub_key: str, principal: str = PRINCIPAL, namespaces: tuple[str, ...] = ()) -> str:
    """One allowed_signers line: `<principal> [namespaces="a,b"] <keytype> <base64>`."""
    parts = pub_key.split()
    opt = f' namespaces="{",".join(namespaces)}"' if namespaces else ""
    return f"{principal}{opt} {parts[0]} {parts[1]}"
