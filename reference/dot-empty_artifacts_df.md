# An empty artifacts data frame matching toolero's accumulator schema

Internal helper used by
[`htc_collect()`](https://erwinlares.github.io/submitr/reference/htc_collect.md)
as the fallback when a job's `project-manifest.json` records zero
artifacts (an analysis that ran and produced nothing –
`toolero::generate_manifest()` warns but still writes a manifest in that
case). Column names mirror `toolero:::.accumulator_columns()`; submitr
keeps its own copy rather than importing an internal function from a
`Suggests`-only dependency.

## Usage

``` r
.empty_artifacts_df()
```

## Value

A zero-row data frame.
