#' Resolve HTC config from argument or session option
#'
#' Internal helper used by `htc_upload()`, `htc_download()`, `htc_submit()`,
#' and `htc_status()` to resolve the config list. Checks the explicit
#' argument first, then falls back to the session option set by
#' `htc_start()`, then errors if neither is available.
#'
#' @param config A named list or `NULL`.
#'
#' @return A validated config list with `username` and `server`.
#'
#' @keywords internal
.resolve_config <- function(config) {

  # 1. Use explicit argument if provided
  if (is.null(config)) {
    # 2. Fall back to session option
    config <- getOption("submitr.config")
  }

  # 3. Error if still NULL
  if (is.null(config)) {
    cli::cli_abort(c(
      "No HTC config found.",
      "i" = "Call {.fn htc_start} to set up your connection,",
      " " = "  or pass a config list from {.fn htc_config} directly."
    ))
  }

  # 4. Validate required fields
  if (is.null(config$username) || is.null(config$server)) {
    cli::cli_abort(c(
      "Config is missing {.val username} or {.val server}.",
      "i" = "Call {.fn htc_start} or {.fn htc_config} to",
      " " = "  generate a valid config."
    ))
  }

  config
}


#' Update the job manifest with new information
#'
#' Internal helper that accumulates job metadata across the submitr
#' pipeline. Each function in the workflow calls `.update_manifest()`
#' with the information it knows. `htc_download()` and `htc_upload()`
#' read the accumulated manifest to resolve files automatically.
#'
#' The manifest is persisted to `htc-manifest.yaml` in `path`, not to
#' session options. Persisting it to disk means the manifest survives
#' across R sessions: restarting a session with [htc_start()] no longer
#' discards job metadata recorded by an earlier call to
#' [htc_gen_submit()], [htc_gen_executable()], or [htc_submit()].
#'
#' Passing `NULL` for a key removes it, which is what makes a single-mode
#' run clear the `subsets` and `subdatasets_path` left behind by an earlier
#' multiple-mode run in the same directory.
#'
#' @param ... Named key-value pairs to add or update in the manifest. Because
#'   `path` below sits after the dots, it is matched exactly by name and can
#'   never be stored as a manifest field. Nothing in the package needs a
#'   field called `path`, but any future one would have to be named
#'   differently.
#' @param path A character string. Directory where `htc-manifest.yaml`
#'   is read from and written to. Defaults to `"."` (current working
#'   directory). Functions that write to a caller-supplied `output`
#'   directory (e.g. [htc_gen_submit()], [htc_gen_executable()]) pass
#'   that directory through so the manifest travels with the generated
#'   files, and so package examples never write outside `tempdir()`.
#'
#' @return Called for its side effects. Returns `invisible(NULL)`.
#'
#' @keywords internal
.update_manifest <- function(..., path = ".") {

  if (!dir.exists(path)) {
    cli::cli_abort(c(
      "Cannot write the job manifest: {.path {path}} does not exist.",
      "i" = "{.arg path} must name an existing directory."
    ))
  }

  manifest_file <- file.path(path, "htc-manifest.yaml")

  current <- if (file.exists(manifest_file)) {
    yaml::read_yaml(manifest_file)
  } else {
    list()
  }
  if (!is.list(current)) {
    current <- list()
  }

  updates <- list(...)
  for (key in names(updates)) {
    current[[key]] <- updates[[key]]
  }

  yaml::write_yaml(current, manifest_file)
  invisible(NULL)
}


#' Retrieve the current job manifest
#'
#' Internal helper that reads the accumulated job manifest from
#' `htc-manifest.yaml` in `path`. Returns `NULL` if no manifest file
#' exists yet.
#'
#' YAML represents a sequence (e.g. a character vector recorded via
#' `.update_manifest()`) as a list on read-back. Each top-level element
#' that is a list of length-1 atomic values is simplified back into an
#' ordinary vector here, so callers see the same shape they originally
#' passed to `.update_manifest()`.
#'
#' @param path A character string. Directory to look for
#'   `htc-manifest.yaml` in. Defaults to `"."` (current working
#'   directory).
#'
#' @return A named list or `NULL`.
#'
#' @keywords internal
.get_manifest <- function(path = ".") {
  manifest_file <- file.path(path, "htc-manifest.yaml")
  if (!file.exists(manifest_file)) {
    return(NULL)
  }

  manifest <- yaml::read_yaml(manifest_file)

  # An empty or unreadable manifest file is treated the same as no manifest
  # at all, so callers only ever have to test for NULL.
  if (!is.list(manifest) || length(manifest) == 0L) {
    return(NULL)
  }

  lapply(manifest, function(x) {
    if (is.list(x) &&
        length(x) > 0L &&
        all(vapply(x, function(e) is.atomic(e) && length(e) == 1L, logical(1)))) {
      unlist(x)
    } else {
      x
    }
  })
}


#' Join a generated file to the directory it was written to
#'
#' Internal helper. The generator functions record two things about each file
#' they write: the bare name, which is what HTCondor sees on the submit node
#' after `scp` flattens the transfer, and the local path, which is what
#' `htc_upload()` needs in order to find the file on this machine. This
#' helper builds the second from the first, leaving the name untouched when
#' `output` is the working directory so that dry-run output reads
#' `job.sub` rather than `./job.sub`.
#'
#' @param output A character string. The directory the file was written to.
#' @param file A character string. The bare filename.
#'
#' @return A character string.
#'
#' @keywords internal
.join_output_path <- function(output, file) {
  if (is.null(output) || identical(output, ".") || identical(output, "./")) {
    file
  } else {
    file.path(output, file)
  }
}


#' Quote a string as a single POSIX shell word
#'
#' Internal helper. Wraps `x` in single quotes, which a POSIX shell treats as
#' entirely literal: no parameter expansion, no command substitution, no
#' globbing, no escape processing. An embedded single quote is handled with
#' the idiom of closing the quoted run, supplying a quote from inside a
#' double-quoted pair, and reopening, so that `a'b` becomes `'a'"'"'b'`.
#'
#' This deliberately does not call [shQuote()]. `shQuote()` chooses between
#' single and double quotes depending on whether its input contains an
#' apostrophe, and its dialect follows the platform R is running on. Both are
#' sensible for quoting a local command and both are wrong here. The far side
#' of an SSH connection is a POSIX shell whatever the researcher's laptop
#' runs, and submitr quotes each command twice, once for the remote shell and
#' once for the local one, so a strategy that varies with its own input
#' composes with itself in ways that have to be reasoned about case by case.
#' Single quotes always, with one escape idiom, does not.
#'
#' The idiom also avoids a backslash, which keeps the `gsub()` replacement
#' below free of escape-processing ambiguity.
#'
#' @param x A character string.
#'
#' @return A character string: `x` as one literal POSIX shell word.
#'
#' @keywords internal
.sh_word <- function(x) {
  paste0("'", gsub("'", "'\"'\"'", x, fixed = TRUE), "'")
}


#' Quote a string for a shell, but only when it needs quoting
#'
#' Internal helper. Quoting every argument is correct but makes `dry_run`
#' output noisy for the ordinary case: a reader checking the command before
#' running it should see `condor_submit job.sub`, not
#' `condor_submit 'job.sub'`. This quotes only strings containing a character
#' a shell would interpret, so the common case is byte-for-byte what submitr
#' produced before quoting existed, while an awkward name such as
#' `Erwin's analysis.sub` still survives intact.
#'
#' @param x A character string.
#'
#' @return A character string, quoted if necessary.
#'
#' @keywords internal
.shell_quote <- function(x) {
  if (grepl("^[A-Za-z0-9._/@:+-]+$", x)) x else .sh_word(x)
}


#' Quote a remote path while leaving a leading tilde expandable
#'
#' Internal helper. Remote paths reach the submit node through two shells:
#' `system2()` runs the `ssh` invocation through a local shell, and `sshd`
#' runs the command string through a shell on the far end. A leading `~` has
#' to survive the first unexpanded and then be expanded by the second, so it
#' cannot simply be handed to `shQuote()`: inside single quotes a tilde is a
#' literal character, and `cd '~/'` fails.
#'
#' The fix is to hold the tilde outside the quotes and quote only what
#' follows. A shell concatenates adjacent quoted and unquoted fragments into
#' a single word, so `~/'my data/'` reaches `cd` as one argument, with the
#' tilde expanded and the space preserved.
#'
#' @param path A character string. A remote directory, possibly beginning
#'   with `~` or `~user`.
#'
#' @return A character string safe to interpolate into a remote command.
#'
#' @keywords internal
.quote_remote_path <- function(path) {
  if (!grepl("^~", path)) {
    return(.shell_quote(path))
  }

  prefix <- sub("^(~[^/]*/?).*$", "\\1", path)
  rest   <- substring(path, nchar(prefix) + 1L)

  if (nchar(rest) == 0L) prefix else paste0(prefix, .shell_quote(rest))
}


#' Derive the stem of an R script's name
#'
#' Internal helper. Strips both the directory and the extension, so that
#' `"R/analysis.R"` and `"analysis.R"` both yield `"analysis"`.
#'
#' The directory half is not cosmetic. The family convention puts a derived
#' script at `R/analysis.R`, and a tarball named from the path rather than
#' the stem would be `R/analysis-results.tar.gz`, written into a directory
#' that does not exist in HTCondor's scratch space. The job would do all of
#' its work and then fail on the final `tar`.
#'
#' @param r_script A character string. The R script's name or path.
#'
#' @return A character string.
#'
#' @keywords internal
.script_stem <- function(r_script) {
  tools::file_path_sans_ext(basename(r_script))
}


#' Build the name of a results tarball
#'
#' Internal helper holding the family's tarball naming convention in one
#' place: `<script stem>[-<subset stem>]-results.tar.gz`, with the subset
#' half present only in multiple mode.
#'
#' The subset stem takes a different form depending on who resolves it, which
#' is why this takes an expression rather than a value. The generated shell
#' script writes `${1%.*}`, resolved on the execute node. The submit file
#' writes `$Fn(file)`, resolved by `condor_submit`. [htc_download()] passes a
#' literal stem it has already computed in R. All three have to agree on the
#' same name for a job's results to survive the trip home, and sharing this
#' function is what makes that structural rather than a matter of three
#' places being edited together.
#'
#' @param script_stem A character string or `NULL`, from `.script_stem()`.
#' @param subset_expr A character string or `NULL`. However the subset stem
#'   is written in the context being generated.
#'
#' @return A character string. At least one of the two parts must be given.
#'
#' @keywords internal
.tarball_name <- function(script_stem = NULL, subset_expr = NULL) {
  parts <- c(script_stem, subset_expr)

  if (length(parts) == 0L) {
    cli::cli_abort(
      "At least one of {.arg script_stem} or {.arg subset_expr} is needed."
    )
  }

  paste0(paste(parts, collapse = "-"), "-results.tar.gz")
}


#' Escape braces so cli renders text literally
#'
#' Internal helper. `cli` treats `{` and `}` in a message as inline markup
#' and evaluates what sits between them. That is exactly wrong for text
#' arriving from somewhere else, such as the output of a remote command: an
#' HTCondor error mentioning a ClassAd expression in braces would be
#' evaluated rather than displayed, and at best produce a confusing error
#' about an object that does not exist. Doubling the braces makes `cli`
#' print them verbatim.
#'
#' @param x A character vector.
#'
#' @return A character vector with braces doubled.
#'
#' @keywords internal
.cli_escape <- function(x) {
  gsub("}", "}}", gsub("{", "{{", x, fixed = TRUE), fixed = TRUE)
}


#' Read a toolero project configuration file
#'
#' Internal helper behind `htc_config()`'s `project_config` argument. Parses
#' a `_toolero.yml` file (the resolved instance `toolero::init_project()`
#' writes to a project's root, not the internal template it renders from)
#' and returns its `folders` and `conventions` sections.
#'
#' Like `.get_manifest()`, this normalizes YAML's round trip: a sequence of
#' scalars (`folders`) comes back from `yaml::read_yaml()` as a list, and
#' callers expect an ordinary character vector.
#'
#' @param path A character string. Path to a `_toolero.yml` file.
#'
#' @return A named list with elements `folders` (a character vector, possibly
#'   `NULL`) and `conventions` (a named list, possibly `NULL`, typically with
#'   `output_dir`, `script_dir`, and `split_dir`).
#'
#' @keywords internal
.read_project_config <- function(path) {
  if (!file.exists(path)) {
    cli::cli_abort(c(
      "Project config file not found: {.path {path}}.",
      "i" = "{.arg project_config} must name an existing",
      " " = "  {.file _toolero.yml} file."
    ))
  }

  project <- yaml::read_yaml(path)

  known_version <- 1L
  if (!is.null(project$schema_version) &&
      !identical(as.integer(project$schema_version), known_version)) {
    cli::cli_warn(c(
      "{.path {path}} declares schema_version {project$schema_version},
             which this version of submitr does not recognize.",
      "i" = "Parsing {.val folders} and {.val conventions} anyway;",
      " " = "  check for a newer submitr release if something looks off."
    ))
  }

  folders <- project$folders
  if (is.list(folders)) {
    folders <- unlist(folders)
  }

  list(
    folders     = folders,
    conventions = project$conventions
  )
}
