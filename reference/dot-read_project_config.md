# Read a toolero project configuration file

Internal helper behind
[`htc_config()`](https://erwinlares.github.io/submitr/reference/htc_config.md)'s
`project_config` argument. Parses a `_toolero.yml` file (the resolved
instance
[`toolero::init_project()`](https://erwinlares.github.io/toolero/reference/init_project.html)
writes to a project's root, not the internal template it renders from)
and returns its `folders` and `conventions` sections.

## Usage

``` r
.read_project_config(path)
```

## Arguments

- path:

  A character string. Path to a `_toolero.yml` file.

## Value

A named list with elements `folders` (a character vector, possibly
`NULL`) and `conventions` (a named list, possibly `NULL`, typically with
`output_dir`, `script_dir`, and `split_dir`).

## Details

Like
[`.get_manifest()`](https://erwinlares.github.io/submitr/reference/dot-get_manifest.md),
this normalizes YAML's round trip: a sequence of scalars (`folders`)
comes back from
[`yaml::read_yaml()`](https://yaml.r-lib.org/reference/read_yaml.html)
as a list, and callers expect an ordinary character vector.
