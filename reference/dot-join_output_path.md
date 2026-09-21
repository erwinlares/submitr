# Join a generated file to the directory it was written to

Internal helper. The generator functions record two things about each
file they write: the bare name, which is what HTCondor sees on the
submit node after `scp` flattens the transfer, and the local path, which
is what
[`htc_upload()`](https://erwinlares.github.io/submitr/reference/htc_upload.md)
needs in order to find the file on this machine. This helper builds the
second from the first, leaving the name untouched when `output` is the
working directory so that dry-run output reads `job.sub` rather than
`./job.sub`.

## Usage

``` r
.join_output_path(output, file)
```

## Arguments

- output:

  A character string. The directory the file was written to.

- file:

  A character string. The bare filename.

## Value

A character string.
