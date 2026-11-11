"""Real Lua 5.2 and 5.3 execution via optional host-only Lupa; no Minecraft required."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / ".tools"))
try:
    from lupa import lua52, lua53
except ImportError:
    raise SystemExit("Install test dependency: python -m pip install --target .tools lupa==2.8")

for engine in (lua52, lua53):
    lua = engine.LuaRuntime(unpack_returned_tuples=True, encoding="utf-8")
    lua.globals().PROJECT_ROOT = ROOT.as_posix()
    lua.globals().READ_PROJECT_FILE = lambda p: Path(p).read_text(encoding="utf-8")
    lua.execute('package.path=PROJECT_ROOT.."/src/?.lua;"..PROJECT_ROOT.."/tests/?.lua;"..package.path')
    # Compile every entry point without executing generated installers.
    for path in sorted(ROOT.rglob("*.lua")):
        if any(part.startswith(".") for part in path.relative_to(ROOT).parts):
            continue
        loaded = lua.eval("load")(path.read_text(encoding="utf-8"), "@" + path.as_posix(), "t")
        if isinstance(loaded, tuple) and loaded[0] is None:
            raise AssertionError(loaded[1])
    print(f"Lua {engine.LUA_VERSION}: syntax OK", flush=True)
    # Windows Lua's C file loader uses ANSI paths; Python supplies UTF-8 sources.
    preload = lua.globals().package.preload
    for path in (ROOT / "src").rglob("*.lua"):
        name = path.relative_to(ROOT / "src").with_suffix("").as_posix().replace("/", ".")
        preload[name] = lua.eval("function(code,name) return assert(load(code,name,'t')) end")(
            path.read_text(encoding="utf-8"), "@src/" + path.relative_to(ROOT / "src").as_posix())
    lua.execute((ROOT / "tests" / "suite.lua").read_text(encoding="utf-8"))
    # Isolated real allocator limit catches snapshot duplication regressions.
    bounded = engine.LuaRuntime(unpack_returned_tuples=True, encoding="utf-8", max_memory=2 * 1024 * 1024)
    for name in ("core.codec", "core.items", "server.ae2", "server.stock"):
        source = (ROOT / "src" / (name.replace(".", "/") + ".lua")).read_text(encoding="utf-8")
        bounded.globals().package.preload[name] = bounded.eval("function(code,name) return assert(load(code,name,'t')) end")(source, name)
    bounded.execute((ROOT / "tests" / "ae2_memory.lua").read_text(encoding="utf-8"))
