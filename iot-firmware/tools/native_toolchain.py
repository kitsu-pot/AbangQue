"""Use the pinned Windows test compiler without changing the user's PATH."""
from os.path import join

Import("env")
compiler_package = env.PioPlatform().get_package_dir("toolchain-gccmingw32")
if not compiler_package:
    raise RuntimeError("Pinned Windows native compiler package is missing")
env.PrependENVPath("PATH", join(compiler_package, "bin"))
# The test runner and the Node contract bridge launch the binary independently of
# SCons's compiler PATH. Link compiler runtimes into it instead of copying DLLs.
env.Append(LINKFLAGS=["-static", "-static-libgcc", "-static-libstdc++"])
