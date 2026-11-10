#!/usr/bin/env python3
"""Minimal App Store Connect API client (ES256 JWT via openssl). Never prints the key."""
import base64, json, os, subprocess, sys, time, hashlib
import requests

KEY_ID = os.environ.get("ASC_KEY_ID", "8D354QTNJP")
ISSUER = os.environ.get("ASC_ISSUER", "f0938118-6ddf-4f94-8304-8b5b283cf219")
KEY = os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8")
BASE = "https://api.appstoreconnect.apple.com"

def b64(b): return base64.urlsafe_b64encode(b).rstrip(b"=").decode()

def _der_to_raw(der):
    # parse ECDSA DER SEQUENCE(INTEGER r, INTEGER s)
    i = 2 if der[1] < 0x80 else 3
    assert der[i] == 2; lr = der[i+1]; r = der[i+2:i+2+lr]; i = i+2+lr
    assert der[i] == 2; ls = der[i+1]; s = der[i+2:i+2+ls]
    return r[-32:].rjust(32, b"\0") + s[-32:].rjust(32, b"\0")

_tok = [None, 0]
def token():
    if _tok[0] and time.time() < _tok[1] - 60: return _tok[0]
    now = int(time.time()); exp = now + 1100
    h = b64(json.dumps({"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}).encode())
    p = b64(json.dumps({"iss": ISSUER, "iat": now, "exp": exp, "aud": "appstoreconnect-v1"}).encode())
    msg = f"{h}.{p}".encode()
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", KEY], input=msg, capture_output=True, check=True).stdout
    _tok[0] = f"{h}.{p}.{b64(_der_to_raw(der))}"; _tok[1] = exp
    return _tok[0]

def req(method, path, body=None, params=None, timeout=60):
    url = path if path.startswith("http") else BASE + path
    r = requests.request(method, url, headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"},
                         json=body, params=params, timeout=timeout)
    if r.status_code >= 400:
        raise RuntimeError(f"{method} {path} -> {r.status_code}: {r.text[:1500]}")
    return r.json() if r.text else {}

def get_all(path, params=None):
    out = []; d = req("GET", path, params=params)
    out += d.get("data", []) if isinstance(d.get("data"), list) else [d.get("data")]
    while d.get("links", {}).get("next"):
        d = req("GET", d["links"]["next"]); out += d.get("data", [])
    return out

def upload_asset(create_path, rel_type, rel_key, parent_id, file_path, extra_attrs=None, timeout=60):
    """Reserve, upload parts, commit with checksum. Returns final resource id."""
    data = open(file_path, "rb").read()
    attrs = {"fileName": os.path.basename(file_path), "fileSize": len(data)}
    attrs.update(extra_attrs or {})
    body = {"data": {"type": create_path.strip("/").split("/")[-1], "attributes": attrs,
                     "relationships": {rel_key: {"data": {"type": rel_type, "id": parent_id}}}}}
    res = req("POST", create_path, body)["data"]
    rid = res["id"]
    try:
        for op in res["attributes"]["uploadOperations"]:
            chunk = data[op["offset"]:op["offset"] + op["length"]]
            hdrs = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
            r = requests.request(op["method"], op["url"], headers=hdrs, data=chunk, timeout=timeout)
            if r.status_code >= 300: raise RuntimeError(f"part upload {r.status_code}: {r.text[:300]}")
        req("PATCH", f"{create_path}/{rid}", {"data": {"type": body["data"]["type"], "id": rid,
            "attributes": ({"uploaded": True} if body["data"]["type"] == "appAssetLibraryImages"
                           else {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()})}})
    except Exception:
        try: req("DELETE", f"{create_path}/{rid}")
        except Exception: pass
        raise
    return rid

if __name__ == "__main__":
    m, p = sys.argv[1], sys.argv[2]
    print(json.dumps(req(m, p, json.loads(sys.argv[3]) if len(sys.argv) > 3 else None), indent=1, ensure_ascii=False)[:20000])
