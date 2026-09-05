test:
    lua tests/run.lua

poc-001-test:
    lua pocs/001-window-events-liveness/run-tests.lua

install:
    ./scripts/install-local.sh

alias l  := list
list:
    @just --list

# Local Variables:
# mode: makefile
# indent-tabs-mode: nil
# End:
