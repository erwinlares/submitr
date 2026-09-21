# Build the name of a results tarball

Internal helper holding the family's tarball naming convention in one
place: `<script stem>[-<subset stem>]-results.tar.gz`, with the subset
half present only in multiple mode.

## Usage

``` r
.tarball_name(script_stem = NULL, subset_expr = NULL)
```

## Arguments

- script_stem:

  A character string or `NULL`, from
  [`.script_stem()`](https://erwinlares.github.io/submitr/reference/dot-script_stem.md).

- subset_expr:

  A character string or `NULL`. However the subset stem is written in
  the context being generated.

## Value

A character string. At least one of the two parts must be given.

## Details

The subset stem takes a different form depending on who resolves it,
which is why this takes an expression rather than a value. The generated
shell script writes `${1%.*}`, resolved on the execute node. The submit
file writes `$Fn(file)`, resolved by `condor_submit`.
[`htc_download()`](https://erwinlares.github.io/submitr/reference/htc_download.md)
passes a literal stem it has already computed in R. All three have to
agree on the same name for a job's results to survive the trip home, and
sharing this function is what makes that structural rather than a matter
of three places being edited together.
