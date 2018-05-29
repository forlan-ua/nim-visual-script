import nimx.naketools
import osproc

beforeBuild = proc(b: Builder) =
    b.disableClosureCompiler = false
    b.mainFile = "main"

task "editor", "Build and run samples":
    newBuilder().build()
