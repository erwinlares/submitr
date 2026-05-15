# NA

## Session — 2026-05-14

### What we set out to do

This session was an end-to-end test of the full notebook-to-cluster
pipeline: `toolero` for project scaffolding, `containr` for
containerization, and `submitr` for job submission to CHTC. The test
project used a simple R script (`ntbk2clstr.R`) analyzing the Palmer
Penguins dataset, with all files baked into the container image via
[`containr::generate_dockerfile()`](https://erwinlares.github.io/containr/reference/generate_dockerfile.html).

The job failed repeatedly. Each failure revealed a bug in either
`containr` or `submitr` that had gone unnoticed in unit testing because
the three-layer test strategy does not include a cross-package
integration test against a live HTCondor cluster.

------------------------------------------------------------------------

### Errors encountered and fixes applied

**Error 1 – absolute paths in Dockerfile COPY instructions.**
[`containr::generate_dockerfile()`](https://erwinlares.github.io/containr/reference/generate_dockerfile.html)
wrote absolute host paths (`/Users/lares/Desktop/...`) into `COPY`
instructions because `.validate_file_arg()` returned
[`normalizePath()`](https://rdrr.io/r/base/normalizePath.html) output.
Podman could not resolve these paths from the build context.

Fix: `.validate_file_arg()` now returns paths relative to
[`getwd()`](https://rdrr.io/r/base/getwd.html) via
[`fs::path_rel()`](https://fs.r-lib.org/reference/path_math.html). Files
outside the build context error immediately. `generate_dockerfile()`
COPY blocks simplified to `glue::glue("COPY {.x} /home/{.x}")`.

**Error 2 – flattened directory structure in container.** `COPY`
destinations used [`basename()`](https://rdrr.io/r/base/basename.html),
so `data-raw/sample.csv` ended up at `/home/data/sample.csv` instead of
`/home/data-raw/sample.csv`. The R script’s relative paths broke inside
the container.

Fix: COPY destinations now mirror the source path under `/home/`. Local
directory structure is preserved.

**Error 3 – missing `docker://` prefix in submit file.**
[`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
wrote `container_image` verbatim. Without the `docker://` prefix,
HTCondor treated the image path as a local file on the submit node and
errored with “no such file or directory.”

Fix:
[`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
now prepends `docker://` automatically if the prefix is missing.

**Error 4 – missing transfer directives in submit file.** The generated
`.sub` file lacked `should_transfer_files = YES` and
`when_to_transfer_output = ON_EXIT`. Without these, HTCondor’s file
transfer mechanism does not activate.

Fix: both directives are now always included in the transfer section.

**Error 5 – arm64 container on x86_64 cluster.** The container was built
on an Apple Silicon Mac, producing an `arm64` image. CHTC execute nodes
are `x86_64` and rejected the image with “Image Architecture arm64 not
compatible with this machine.” Building with `--platform linux/amd64`
via Podman failed due to QEMU emulation segfaults. Docker Desktop’s
`buildx` handled the cross-platform build successfully.

Fix: `containr::build_image()` gained a `platform` parameter defaulting
to `"linux/amd64"`. When Docker is the tool and the target platform
differs from the host, the function automatically uses
`docker buildx build` with `--load`.

**Error 6 – HTCondor working directory mismatch.** HTCondor starts the
executable from a scratch directory, not the container’s `WORKDIR`. The
generated `.sh` script used relative paths (`Rscript ntbk2clstr.R`)
which resolved against the scratch directory where the files did not
exist.

Fix:
[`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md)
now emits `cd /home` before any file operations, ensuring paths resolve
against the container’s baked-in file layout.

**Error 7 – silent failures in executable script.** The generated `.sh`
script lacked `set -euo pipefail`. Failed commands (e.g. a missing file)
did not stop the script, making debugging harder.

Fix:
[`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md)
now emits `set -euo pipefail` immediately after the shebang line.

------------------------------------------------------------------------

### What worked after all fixes

The manually corrected `.sub` and `.sh` files ran successfully on CHTC.
The job executed inside the container, found the R script and data at
their expected paths under `/home/`, produced output in the `results/`
folder, and the tarball transferred back to the submit node.

The fixes were then reverse-engineered into
[`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
and
[`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md)
so that the generated files match the working versions without manual
edits.

------------------------------------------------------------------------

### Packages modified

- **containr**: `.validate_file_arg()` relative paths,
  `generate_dockerfile()` COPY simplification, `build_image()` platform
  parameter and buildx support
- **submitr**:
  [`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
  docker:// prefix and transfer directives,
  [`htc_gen_executable()`](https://erwinlares.github.io/submitr/reference/htc_gen_executable.md)
  set -euo pipefail and cd /home

------------------------------------------------------------------------

### Testing

- `containr`: updated `test-generate-dockerfile-content.R` and
  `test-container-workflow.R` for COPY paths, platform, and buildx
- `submitr`: updated `test-htc-gen-submit.R` (docker:// prefix, transfer
  directives) and `test-htc-gen-executable.R` (set -euo pipefail, cd
  /home, section ordering)

------------------------------------------------------------------------

### Open questions carried forward

- `transfer_input_files` design question: should
  [`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md)
  distinguish between files baked into the container and files
  transferred at runtime? The current function lists all files in
  `transfer_input_files` regardless of whether they exist inside the
  container image.
- GitHub Actions workflow for building and pushing `linux/amd64` images
  from Apple Silicon without QEMU emulation (scoped in `containr`
  PLAN.md).
