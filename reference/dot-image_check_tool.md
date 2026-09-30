# The container tool htc_check() asks about an image, if any

Internal helper used by
[`htc_check()`](https://erwinlares.github.io/submitr/reference/htc_check.md):
`"podman"` if it is on the local `PATH`, otherwise `"docker"` if that
is, otherwise `NULL`. A function of its own so the test suite can
replace it: calling a real container tool during `R CMD check` can leave
a directory of the tool's own behind in the check's temporary directory
(podman's `storage-run-<uid>`), which the check reports as detritus.

## Usage

``` r
.image_check_tool()
```

## Value

`"podman"`, `"docker"`, or `NULL`.
