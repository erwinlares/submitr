# Locate the resource presets file

Internal helper used by
[`htc_gen_submit()`](https://erwinlares.github.io/submitr/reference/htc_gen_submit.md).
Returns the local `htc-resources.yml` in `dir` when there is one;
otherwise a local `htc-resources.yaml`, the name submitr 0.1.0 used,
with a warning asking for it to be renamed (read for this release only);
otherwise the package default in `inst/extdata/`. When both local names
exist, the `.yml` file wins and a warning says the `.yaml` file is being
ignored, so a stale copy never silently shadows or is silently shadowed
by the current one.

## Usage

``` r
.resources_file(dir = getwd())
```

## Arguments

- dir:

  A character string. Directory to look in for a local file, normally
  the working directory.

## Value

A single character string: the path to read.
