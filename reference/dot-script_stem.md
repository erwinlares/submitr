# Derive the stem of an R script's name

Internal helper. Strips both the directory and the extension, so that
`"R/analysis.R"` and `"analysis.R"` both yield `"analysis"`.

## Usage

``` r
.script_stem(r_script)
```

## Arguments

- r_script:

  A character string. The R script's name or path.

## Value

A character string.

## Details

The directory half is not cosmetic. The family convention puts a derived
script at `R/analysis.R`, and a tarball named from the path rather than
the stem would be `R/analysis-results.tar.gz`, written into a directory
that does not exist in HTCondor's scratch space. The job would do all of
its work and then fail on the final `tar`.
