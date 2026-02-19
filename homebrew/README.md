# Homebrew Multi-Account Group Setup

Run Homebrew without `sudo` across multiple macOS user accounts using a shared group.

## The Problem

On macOS, Homebrew installs to `/opt/homebrew` (Apple Silicon) or `/usr/local` (Intel). By default, only the user who installed it owns those files. Other accounts get `Permission denied` errors.

Common symptoms:
- `Permission denied @ rb_sysopen` on `.formula.lock` files
- `Permission denied @ rb_file_s_rename` during bottle extraction
- `cp: utimensat: ... Permission denied` from `com.apple.provenance` xattr
- `cp: chmod: ... Operation not permitted`

## The Solution

1. Create a shared group (e.g. `developer`)
2. Add all accounts that need Homebrew to that group
3. Set ownership, permissions, and setgid bits on the Homebrew prefix
4. Strip macOS quarantine/provenance xattrs
5. Set umask so new files stay group-writable

## Quick Start

```bash
# 1. Create the group and add users (requires admin)
sudo dseditgroup -o create developer
sudo dseditgroup -o edit -a yourusername -t user developer
sudo dseditgroup -o edit -a otherusername -t user developer

# 2. Run the setup script
sudo ./setup-brew-group.sh developer

# 3. Add to each user's ~/.zshrc (or ~/.bashrc)
echo 'umask 002' >> ~/.zshrc
echo 'export HOMEBREW_NO_QUARANTINE=1' >> ~/.zshrc
```

Log out and back in for group membership to take effect.

## What the Script Does

1. Sets group ownership of the Homebrew prefix to `developer`
2. Makes everything group-writable (`g+w`)
3. Sets the setgid bit on all directories (`g+s`) — new files/dirs inherit the group
4. Strips `com.apple.provenance` extended attributes that block `cp -pR`
5. Fixes `/private/tmp` permissions (used by Homebrew for unpacking bottles)

## Why setgid?

Without setgid, new files created by any user default to their primary group (usually `staff`), not `developer`. The setgid bit on directories forces new entries to inherit the directory's group, keeping everything accessible.

## Why strip `com.apple.provenance`?

macOS Ventura+ tags downloaded files with a provenance xattr. When Homebrew's `cp -pR` tries to preserve permissions on files with this attribute, the kernel blocks it. Setting `HOMEBREW_NO_QUARANTINE=1` prevents future quarantine, and the script strips existing ones.

## Supported Platforms

- macOS Ventura (13+), Sonoma (14+), Sequoia (15+)
- Apple Silicon (`/opt/homebrew`) and Intel (`/usr/local`)
- Homebrew 4.x+

## Troubleshooting

**Group membership not working?**
Log out and back in. Verify with `id` — you should see `developer` in the groups list.

**Still getting permission errors after running the script?**
Check your umask: `umask`. Should be `002`, not `022`.

**Errors on `brew update`?**
The Git repos under `$(brew --repository)` also need group write. The script handles this, but if you installed new taps manually, re-run the script.
