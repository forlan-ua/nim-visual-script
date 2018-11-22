import nimx.naketools
import osproc, os

beforeBuild = proc(b: Builder) =
    b.disableClosureCompiler = false
    b.mainFile = "tests/main"

task "editor", "Build and run samples":
    newBuilder().build()

task "tests", "Run tests":
    createDir("build")
    direShell(nimExe, "c", "--run", "-d:release", "--out:build/easyapp", "--nimcache:/tmp/nimcache", "visual_script_tests")
