# Quote a string for a shell, but only when it needs quoting

Internal helper. Quoting every argument is correct but makes `dry_run`
output noisy for the ordinary case: a reader checking the command before
running it should see `condor_submit job.sub`, not
`condor_submit 'job.sub'`. This quotes only strings containing a
character a shell would interpret, so the common case is byte-for-byte
what submitr produced before quoting existed, while an awkward name such
as `Erwin's analysis.sub` still survives intact.

## Usage

``` r
.shell_quote(x)
```

## Arguments

- x:

  A character string.

## Value

A character string, quoted if necessary.
