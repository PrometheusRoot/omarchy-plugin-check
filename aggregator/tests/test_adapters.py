import base64
import json
import shutil
import urllib.request
from pathlib import Path
from typing import Any, cast

import pytest

from opc_aggregator import sshsig, state
from opc_aggregator.fetch import HttpsFetcher, LocalFetcher, RoutingFetcher
from opc_aggregator.model import parse_provider
from opc_aggregator.ports import FetchError, VerificationError
from opc_aggregator.sigstore_verifier import SigstoreVerifier
from opc_aggregator.unsigned import UnsignedDevVerifier

from .helpers import provider, provider_doc

DATA = Path(__file__).parent / "data" / "sigstore"
GH_BUNDLE = (DATA / "gh-cli-v2.102.0-provenance.sigstore.json").read_bytes()
needs_ssh = pytest.mark.skipif(shutil.which("ssh-keygen") is None, reason="ssh-keygen missing")


# --- sigstore (recorded public-good bundle: GitHub CLI v2.102.0 build provenance) ------------


@pytest.fixture(scope="module")
def sig():
    return SigstoreVerifier(offline=True)


def test_sigstore_accepts_recorded_bundle_with_exact_identity(sig):
    p = parse_provider(provider_doc(signing="sigstore"))
    v = sig.verify_attestation(p, GH_BUNDLE)
    stmt = json.loads(v.payload)
    assert stmt["_type"] == "https://in-toto.io/Statement/v1"
    assert v.verification == "sigstore"
    assert v.signer == p.identity
    assert v.signed_at is not None
    assert v.signed_at.year == 2026


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("certificateIdentity", "https://github.com/cli/cli/.github/workflows/other.yml@refs/heads/trunk"),
        ("oidcIssuer", "https://accounts.google.com"),
        ("repository", "evil/cli"),
    ],
)
def test_sigstore_rejects_wrong_identity(sig, field, value):
    doc = provider_doc(signing="sigstore")
    doc["sigstore"][field] = value
    with pytest.raises(VerificationError):
        sig.verify_attestation(parse_provider(doc), GH_BUNDLE)


def test_sigstore_rejects_tampered_payload(sig):
    bundle = json.loads(GH_BUNDLE)
    stmt = json.loads(base64.b64decode(bundle["dsseEnvelope"]["payload"]))
    stmt["predicate"]["buildDefinition"]["externalParameters"]["workflow"]["ref"] = "refs/heads/evil"
    bundle["dsseEnvelope"]["payload"] = base64.b64encode(json.dumps(stmt).encode()).decode()
    with pytest.raises(VerificationError):
        sig.verify_attestation(parse_provider(provider_doc(signing="sigstore")), json.dumps(bundle).encode())


def test_sigstore_rejects_garbage_missing_identity_and_missing_index_bundle(sig):
    p = parse_provider(provider_doc(signing="sigstore"))
    with pytest.raises(VerificationError, match="not a sigstore bundle"):
        sig.verify_attestation(p, b"{}")
    with pytest.raises(VerificationError, match="no sigstore identity"):
        sig.verify_attestation(provider(), GH_BUNDLE)
    with pytest.raises(VerificationError, match="missing"):
        sig.verify_blob(p, b"data", None)


def test_sigstore_blob_rejects_wrong_data(sig):
    p = parse_provider(provider_doc(signing="sigstore"))
    with pytest.raises(VerificationError):
        sig.verify_blob(p, b"not the tarball", GH_BUNDLE)


class _FakeSig:
    def __init__(self, ptype):
        self.ptype = ptype

    def verify_dsse(self, bundle, policy):
        return self.ptype, b"{}"

    def verify_artifact(self, data, bundle, policy):
        return None


def test_sigstore_payload_type_and_blob_success_paths():
    p = parse_provider(provider_doc(signing="sigstore"))
    with pytest.raises(VerificationError, match="payloadType"):
        SigstoreVerifier(cast("Any", _FakeSig("text/plain"))).verify_attestation(p, GH_BUNDLE)
    v = SigstoreVerifier(cast("Any", _FakeSig("x"))).verify_blob(p, b"idx", GH_BUNDLE)
    assert (v.payload, v.verification) == (b"idx", "sigstore")


# --- unsigned dev verifier ---------------------------------------------------------------------


def test_unsigned_dev_verifier():
    u = UnsignedDevVerifier()
    p = provider()
    assert u.verify_attestation(p, b'{"a": 1}').payload == b'{"a": 1}'
    env = {
        "payloadType": "application/vnd.in-toto+json",
        "payload": base64.b64encode(b'{"b":2}').decode(),
        "signatures": [],
    }
    v = u.verify_attestation(p, json.dumps(env).encode())
    assert (v.payload, v.verification) == (b'{"b":2}', "unsigned-dev")
    with pytest.raises(VerificationError, match="payloadType"):
        u.verify_attestation(p, json.dumps({**env, "payloadType": "x"}).encode())
    with pytest.raises(VerificationError, match="bad DSSE"):
        u.verify_attestation(p, json.dumps({**env, "payload": "!!"}).encode())
    with pytest.raises(VerificationError, match="not JSON"):
        u.verify_attestation(p, b"{")
    assert u.verify_blob(p, b"x", None).payload == b"x"


# --- fetchers ----------------------------------------------------------------------------------


def test_local_fetcher_stays_inside_root(tmp_path):
    (tmp_path / "a.json").write_text("{}")
    f = LocalFetcher(tmp_path)
    assert f.get(str(tmp_path / "a.json")) == b"{}"
    with pytest.raises(FetchError, match="outside"):
        f.get(str(tmp_path / ".." / "etc" / "passwd"))
    with pytest.raises(FetchError):
        f.get(str(tmp_path / "missing.json"))


def test_https_fetcher_refuses_other_schemes_and_routing(tmp_path):
    with pytest.raises(FetchError, match="non-https"):
        HttpsFetcher().get("http://example.com/x")
    with pytest.raises(FetchError, match="not allowed"):
        RoutingFetcher(HttpsFetcher(), None).get(str(tmp_path))
    (tmp_path / "x").write_text("1")
    assert RoutingFetcher(HttpsFetcher(), LocalFetcher(tmp_path)).get(str(tmp_path / "x")) == b"1"


class _Resp:
    def __init__(self, body):
        self.body = body

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def read(self, n):
        return self.body[:n]


def test_https_fetcher_size_cap_and_errors(monkeypatch):
    monkeypatch.setattr(urllib.request, "urlopen", lambda req, timeout: _Resp(b"x" * 20))
    assert HttpsFetcher(max_bytes=20).get("https://e.example/a") == b"x" * 20
    with pytest.raises(FetchError, match="larger"):
        HttpsFetcher(max_bytes=10).get("https://e.example/a")
    assert RoutingFetcher(HttpsFetcher(max_bytes=20), None).get("https://e.example/a") == b"x" * 20

    def boom(req, timeout):
        raise OSError("down")

    monkeypatch.setattr(urllib.request, "urlopen", boom)
    with pytest.raises(FetchError, match="down"):
        HttpsFetcher().get("https://e.example/a")


# --- state + ssh signatures --------------------------------------------------------------------


def test_state_roundtrip(tmp_path):
    p = tmp_path / "s" / "state.json"
    assert state.load(p) == state.State()
    st = state.State(registry=3, feeds={"opc": 9}, snapshot=11)
    state.save(p, st)
    assert state.load(p) == st


@needs_ssh
def test_ssh_sign_verify_namespaces(tmp_path):
    key = tmp_path / "k" / "key"
    sshsig.keygen(key, "test key")
    assert oct(key.stat().st_mode & 0o777) == "0o600"
    pub = key.with_name("key.pub").read_text()
    allowed = tmp_path / "allowed"
    allowed.write_text(sshsig.allowed_signers_line(pub, namespaces=("ns-a",)) + "\n")
    data = tmp_path / "store.json"
    data.write_text('{"v":1}')
    sig = sshsig.sign(data, key, "ns-a")
    assert sig.name == "store.json.sig"
    assert sshsig.verify(data.read_bytes(), sig, allowed, "ns-a")
    assert not sshsig.verify(b'{"v":2}', sig, allowed, "ns-a")
    assert not sshsig.verify(data.read_bytes(), sig, allowed, "ns-b")
    assert not sshsig.verify(data.read_bytes(), sig, allowed, "ns-a", principal="someone-else")
    assert sshsig.allowed_signers_line(pub).startswith("omarchy-plugin-check ssh-ed25519 ")


@needs_ssh
def test_ssh_errors(tmp_path, monkeypatch):
    with pytest.raises(sshsig.SshSigError):
        sshsig.sign(tmp_path / "missing", tmp_path / "nokey", "ns")
    monkeypatch.setattr(sshsig, "_ssh_keygen", lambda: shutil.which("false"))
    with pytest.raises(sshsig.SshSigError):
        sshsig.keygen(tmp_path / "k1", "c")
    monkeypatch.undo()
    monkeypatch.setattr(shutil, "which", lambda name: None)
    with pytest.raises(sshsig.SshSigError, match="not found"):
        sshsig.keygen(tmp_path / "k2", "c")
