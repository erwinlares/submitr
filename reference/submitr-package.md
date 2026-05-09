# submitr: Scaffold and Submit Computational Jobs to HTC Schedulers

Provides scaffolding tools to help researchers prepare and submit
computational jobs to high-throughput computing (HTC) schedulers.
Generates the files required to run containerized R analyses on
'HTCondor', including submit files and executable scripts, and wraps the
system commands needed to stage files, submit jobs, monitor status, and
retrieve results from a CHTC submit node. Provides 'htc_config()' for
managing connection details and SSH connection reuse guidance. Works
naturally alongside 'containr' for container image management and
'toolero' for dataset splitting and project scaffolding. 'HTCondor' and
'CHTC' are the initial targets; 'HPC' scheduler support ('Slurm', 'PBS')
is planned for a future release.

## See also

Useful links:

- <https://erwinlares.github.io/submitr/>

## Author

**Maintainer**: Erwin Lares <erwin.lares@wisc.edu>
([ORCID](https://orcid.org/0000-0002-3284-828X))

Authors:

- Erwin Lares <erwin.lares@wisc.edu>
  ([ORCID](https://orcid.org/0000-0002-3284-828X))
