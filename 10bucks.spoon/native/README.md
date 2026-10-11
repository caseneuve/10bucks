# Exact-resource AX worker

Required for the focused silent-close safety seam. One production implementation;
no synchronous polling fallback or test delay.

On the supported Apple Silicon host with Hammerspoon 1.1.1 installed:

```sh
./10bucks.spoon/native/build.sh
```

Requires Xcode Command Line Tools/clang and installed LuaSkin headers. Produces
ignored `native/build/ax_validity.so`; functional runner builds and snapshots it
before launch. Build failure must be resolved before loading the candidate.

The bridge retains the original Hammerspoon AX resource, queries AXRole on one
serial worker, and publishes primitive results through a bounded mailbox. Only
InvalidUIElement authorizes normalized removal. Lua/reducer work stays on main.

The native image is pinned for the Hammerspoon process lifetime with public
RTLD_NODELETE to protect in-flight worker code across Lua reload. Stop cancels and
suppresses results immediately; worker drain is asynchronous. After changing the
native implementation, use a fresh binary path or restart Hammerspoon deliberately
rather than overwrite an image already loaded from the same path. Do not edit a
frozen binary/source behind a running candidate.

Evidence/qualifications: `docs/pocs/017-asynchronous-exact-ax-validity.md`.
