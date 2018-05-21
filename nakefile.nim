import nimx.naketools
import osproc

beforeBuild = proc(b: Builder) =
    b.disableClosureCompiler = false
    b.mainFile = "editor/main"

task "editor", "Build and run samples":
    newBuilder().build()
