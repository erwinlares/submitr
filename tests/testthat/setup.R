# tests/testthat/setup.R
#
# htc_check() asks podman or docker, when either is on PATH, whether a
# container image is pullable. Letting it do so during the test suite
# contacts a registry, makes results depend on the machine, and leaves a
# storage-run-<uid> directory in R CMD check's temporary directory, which
# the check reports as detritus. For the whole suite, htc_check() finds no
# container tool; tests of the probe itself replace .image_check_tool()
# and .inspect_image() locally.
local_mocked_bindings(
    .image_check_tool = function() NULL,
    .env = testthat::teardown_env()
)
