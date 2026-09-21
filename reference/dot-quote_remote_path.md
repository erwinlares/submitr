# Quote a remote path while leaving a leading tilde expandable

Internal helper. Remote paths reach the submit node through two shells:
[`system2()`](https://rdrr.io/r/base/system2.html) runs the `ssh`
invocation through a local shell, and `sshd` runs the command string
through a shell on the far end. A leading `~` has to survive the first
unexpanded and then be expanded by the second, so it cannot simply be
handed to [`shQuote()`](https://rdrr.io/r/base/shQuote.html): inside
single quotes a tilde is a literal character, and `cd '~/'` fails.

## Usage

``` r
.quote_remote_path(path)
```

## Arguments

- path:

  A character string. A remote directory, possibly beginning with `~` or
  `~user`.

## Value

A character string safe to interpolate into a remote command.

## Details

The fix is to hold the tilde outside the quotes and quote only what
follows. A shell concatenates adjacent quoted and unquoted fragments
into a single word, so `~/'my data/'` reaches `cd` as one argument, with
the tilde expanded and the space preserved.
