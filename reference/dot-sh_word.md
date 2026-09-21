# Quote a string as a single POSIX shell word

Internal helper. Wraps `x` in single quotes, which a POSIX shell treats
as entirely literal: no parameter expansion, no command substitution, no
globbing, no escape processing. An embedded single quote is handled with
the idiom of closing the quoted run, supplying a quote from inside a
double-quoted pair, and reopening, so that `a'b` becomes `'a'"'"'b'`.

## Usage

``` r
.sh_word(x)
```

## Arguments

- x:

  A character string.

## Value

A character string: `x` as one literal POSIX shell word.

## Details

This deliberately does not call
[`shQuote()`](https://rdrr.io/r/base/shQuote.html).
[`shQuote()`](https://rdrr.io/r/base/shQuote.html) chooses between
single and double quotes depending on whether its input contains an
apostrophe, and its dialect follows the platform R is running on. Both
are sensible for quoting a local command and both are wrong here. The
far side of an SSH connection is a POSIX shell whatever the researcher's
laptop runs, and submitr quotes each command twice, once for the remote
shell and once for the local one, so a strategy that varies with its own
input composes with itself in ways that have to be reasoned about case
by case. Single quotes always, with one escape idiom, does not.

The idiom also avoids a backslash, which keeps the
[`gsub()`](https://rdrr.io/r/base/grep.html) replacement below free of
escape-processing ambiguity.
