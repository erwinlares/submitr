# Parse a request_memory/request_disk-style size string into gigabytes

Internal helper used by
[`htc_check()`](https://erwinlares.github.io/submitr/reference/htc_check.md)
to compare `resources` values like `"16GB"`, `"512MB"`, or a bare `"4"`
(HTCondor treats an amount with no unit suffix as megabytes for
`request_memory`/`request_disk`) on a common scale. Never authoritative
– it exists to catch an obviously implausible request (a stray extra
zero, GB where MB was meant), not to validate HTCondor's own
resource-request syntax exhaustively.

## Usage

``` r
.parse_size_gb(x)
```

## Arguments

- x:

  A character string, or `NULL`/`NA`.

## Value

A numeric scalar in gigabytes, or `NA_real_` if `x` cannot be parsed.
