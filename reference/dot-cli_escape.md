# Escape braces so cli renders text literally

Internal helper. `cli` treats `{` and `}` in a message as inline markup
and evaluates what sits between them. That is exactly wrong for text
arriving from somewhere else, such as the output of a remote command: an
HTCondor error mentioning a ClassAd expression in braces would be
evaluated rather than displayed, and at best produce a confusing error
about an object that does not exist. Doubling the braces makes `cli`
print them verbatim.

## Usage

``` r
.cli_escape(x)
```

## Arguments

- x:

  A character vector.

## Value

A character vector with braces doubled.
