# Ask a container tool whether an image is pullable

Internal helper used by
[`htc_check()`](https://erwinlares.github.io/submitr/reference/htc_check.md).
Runs `<tool> manifest inspect <image>` with a 15-second timeout and
returns its exit status, treating an error or a warning from
[`system2()`](https://rdrr.io/r/base/system2.html) as a failure (`1L`).

## Usage

``` r
.inspect_image(tool, image)
```

## Arguments

- tool:

  Character. `"podman"` or `"docker"`.

- image:

  Character. The image reference, without `docker://`.

## Value

An integer exit status; `0L` means the tool found the image.
