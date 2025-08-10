# Installing xxHash for Faster Checksums

ImageIntact now supports xxHash128 which is **significantly faster** than SHA-256 for checksum verification.

## Installation via Homebrew (Recommended)

```bash
# Install Homebrew if you don't have it
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install xxhash
brew install xxhash
```

## Installation via MacPorts

```bash
sudo port install xxhash
```

## Verification

After installation, verify it's working:

```bash
xxhsum --version
```

## Performance Difference

- **SHA-256**: ~500 MB/s (what we use without xxHash)
- **xxHash128**: ~15 GB/s (30x faster!)

For a 1GB photo file:
- SHA-256: ~2 seconds
- xxHash128: ~0.07 seconds

## Automatic Detection

ImageIntact automatically detects if xxhsum is available:
- ✅ If found: Uses lightning-fast xxHash128
- 🐢 If not found: Falls back to reliable SHA-256

No configuration needed - it just works faster when xxHash is available!