# Rootfs archive

These ordinary Git files are consecutive parts of
`rootfs-trixie-armhf.tar.gz`. They are split because GitHub rejects individual
files over 100 MB; Git LFS is not required.

Run `../scripts/reconstruct-rootfs.sh` from any directory. It concatenates the
parts in order and verifies the original archive SHA-256:

```text
9d869bf8f45f6f3908097aece847bb2d1bde4a6213801cb8460cdb83f9a30eb6
```

Verify the parts independently with `shasum -a 256 -c rootfs/SHA256SUMS`.
