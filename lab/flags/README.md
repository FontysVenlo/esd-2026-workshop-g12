# Flags

This folder holds the capture-the-flag secrets (`level1.txt` … `level7.txt`) that
live on the victim host during the lab. For Level 7 the flag is also copied onto a
small loopback "data disk" at runtime (see `lab/host/scripts/levels.conf`,
`_build_level7_disk`), so it can be reached with the `open_by_handle_at` escape.

The flag files are made fresh and unique on every `./lab.sh up`, and they are
git-ignored (see the repo `.gitignore`). This is on purpose: if the flags were
committed, people could just read the answers from the repository instead of
actually doing the escape.

- The generation happens in `lab.sh` (`gen_flags`), which also writes the expected
  values to `.build/answers`, so `./lab.sh submit` can check them.
- Format: `ESD26{<technique>_<random hex>}`, for example `ESD26{bind_mount_ab12cd34...}`.

You will not see any `*.txt` files here until you run `./lab.sh up`.
