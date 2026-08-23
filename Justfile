test:
    lua tests/run.lua

install:
    ./scripts/install-local.sh

alias l  := list
list:
    @just --list

# Local Variables:
# mode: makefile
# indent-tabs-mode: nil
# End:
