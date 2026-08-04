---
name: writing-install-scripts
description: Use when creating or reviewing an install-*.sh script in this repo that downloads a third-party binary/package and must cryptographically verify it before and after installation.
---

# Writing `install-*.sh` scripts

Every `scripts/install-*.sh` in this repo downloads a pinned third-party
dependency and must verify it twice: once right after download, and once
again on the on-disk installed artifact. The verification method depends on
whether the artifact is code-signed.

## Decision: is the artifact signed?

- **macOS `.pkg` installers** are almost always signed with a Developer ID
  Installer certificate. Check with `pkgutil --check-signature file.pkg`.
- **Bare binaries / zips** (e.g. rustfs) are often unsigned. Check with
  `codesign -dv <binary>` — "code object is not signed at all" means unsigned.

Never assume; always check the actual artifact for the dependency you're adding.

## Case 1: Signed artifact (e.g. munkitools, swiftpkg, AWS CLI)

Verify identity, not just "is it signed" — an attacker can self-sign. Pin the
expected issuer name AND Team ID, and require both to match.

**At download time** (verify the downloaded `.pkg`):

```bash
EXPECTED_ISSUER="Some Company, LLC"
EXPECTED_TEAM_ID="ABCD1234EF"

verify_package() {
    local pkg_path="$1"
    if ! command -v pkgutil &> /dev/null; then
        echo "❌ ERROR: pkgutil is not available. Cannot verify package signature."
        return 1   # hard fail — never skip verification if the tool is missing
    fi

    if ! pkgutil --check-signature "$pkg_path" &>/dev/null; then
        echo "❌ ERROR: Package signature verification failed"
        return 1
    fi

    CERT_INFO=$(pkgutil --check-signature "$pkg_path" 2>&1)
    ACTUAL_ISSUER=$(echo "$CERT_INFO" | grep "Developer ID Installer:" | head -1 | sed 's/.*Developer ID Installer: //' | sed 's/ (.*//')
    ACTUAL_TEAM_ID=$(echo "$CERT_INFO" | grep "Developer ID Installer:" | head -1 | grep -oE '\([A-Z0-9]+\)' | tr -d '()')

    [ "$ACTUAL_ISSUER" = "$EXPECTED_ISSUER" ] || { echo "❌ Issuer mismatch: got $ACTUAL_ISSUER"; return 1; }
    [ "$ACTUAL_TEAM_ID" = "$EXPECTED_TEAM_ID" ] || { echo "❌ Team ID mismatch: got $ACTUAL_TEAM_ID"; return 1; }
    return 0
}
```

**At install time** (verify the on-disk installed binary — no hash needed,
codesign is a stronger and version-independent guarantee):

```bash
verify_installed_binary() {
    local bin_path="$1"

    # --verify only proves the binary matches its own embedded signature.
    # This is TRUE EVEN FOR AD-HOC SIGNATURES, which anyone (including an
    # attacker) can apply locally with `codesign -s -`. It does NOT prove
    # who signed the binary. Never trust --verify alone.
    if ! codesign --verify --strict "$bin_path" &>/dev/null; then
        echo "❌ Error: signature verification failed"
        return 1
    fi

    # You MUST also check the Team ID to prove authenticity.
    local team_id
    team_id=$(codesign -dvv "$bin_path" 2>&1 | grep "^TeamIdentifier=" | cut -d= -f2)
    if [ "$team_id" != "$EXPECTED_TEAM_ID" ]; then
        echo "❌ Error: Team ID mismatch (expected $EXPECTED_TEAM_ID, got ${team_id:-not set})"
        return 1
    fi
    return 0
}
```

⚠️ **Verified pitfall (reproduced locally)**: a binary with an ad-hoc signature
(e.g. many Homebrew/Rust/Go tools, `TeamIdentifier=not set` in `codesign -dvv`
output) passes `codesign --verify --strict` with exit code 0. That check alone
proves *integrity since signing*, not *authenticity of the signer*. Always
pair it with the Team ID check above — never ship `--verify --strict` as the
only guard on an installed binary.

⚠️ **Common bug**: `codesign -v -strict` (single dash) is also WRONG. `-s` is
the "sign identity" flag and consumes the rest of `-strict` as its argument,
producing a bogus `trict: no identity found` error. Always write
`--verify --strict` (double dash), or `-v --strict`. Test locally with
`codesign --verify --strict <bin>; echo $?` and separately confirm the Team ID
check actually rejects an unrelated ad-hoc-signed binary before trusting it in CI.

Do NOT also pin a SHA256 of a signed binary — the signature already proves
authenticity and integrity, and the binary content can legitimately change
between rebuilds of the same version (timestamps, re-signing) which would
break a hash pin for no security benefit.

## Case 2: Unsigned artifact (e.g. rustfs)

There's no identity to check, so SHA256 hash pinning is the only option —
but you need **two separate pinned hashes**, because the downloaded archive
and the installed/extracted artifact are different files with different bytes:

```bash
RUSTFS_ZIP_SHA256="..."      # hash of the downloaded .zip
RUSTFS_BINARY_SHA256="..."   # hash of the extracted/installed binary itself
```

**At download time**, verify the downloaded archive against `*_ZIP_SHA256` (or
whatever the raw download format is) before extracting anything.

**At install time**, verify the actual on-disk binary (after unzip/copy)
against `*_BINARY_SHA256`. This is a *different* hash than the zip's hash —
don't reuse the download hash for the installed binary or verification will
always fail.

```bash
verify_binary() {
    local path="$1"
    local actual_sha=$(sha256sum "$path" | awk '{print $1}')
    [ "$actual_sha" = "$PINNED_BINARY_SHA256" ] || { echo "❌ hash mismatch"; return 1; }
    return 0
}
# call once after download/extract, and again after copying to final install dir
```

## Summary table

| Artifact type      | Download-time check                  | Install-time check                      |
|---------------------|---------------------------------------|-------------------------------------------|
| Signed (.pkg)       | `pkgutil --check-signature` + issuer/Team ID match | `codesign --verify --strict` on installed binary **and** Team ID match |
| Unsigned (binary/zip) | SHA256 of downloaded archive         | SHA256 of the on-disk installed binary (separate pinned hash) |

## Other conventions used in this repo's install scripts

- `set -e` at the top.
- Idempotency: if the tool is already installed, verify it and exit 0 rather
  than reinstalling.
- `--install` flag gates actual installation (dry-run by default shows what
  would happen); `--help` prints usage.
- Use a `mktemp -d` scratch dir with `trap "rm -rf $TEMP_DIR" EXIT` for
  downloads that need cleanup, rather than hardcoding `/tmp/<file>`.
- Hard-fail (`return 1` / `exit 1`) if a required verification tool
  (`pkgutil`, `codesign`, `sha256sum`) is missing — never silently skip
  verification.
- Pin exact upstream version/tag in a variable at the top of the script with
  a comment noting who signs it (issuer + Team ID) or that it's unsigned.
