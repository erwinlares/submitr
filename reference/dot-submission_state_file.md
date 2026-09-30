# File name of the submission state

Internal helper returning the name of the file the submission state is
kept in, `htc-manifest.yml`. Every reader and writer goes through it, so
the name lives in one place. The family writes YAML files with the
`.yml` extension (toolero's `CONVENTIONS.md`, section 8). Development
versions before 0.2.0 wrote `htc-manifest.yaml`; none of them reached
CRAN, so there is no fallback to the old name.

## Usage

``` r
.submission_state_file()
```

## Value

A single character string.
