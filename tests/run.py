#!/usr/bin/env python3
"""
Executa a suíte de testes em Lua (tests/lua) usando o interpretador Lua embutido
no pacote 'lupa', e depois os testes em Python (tests/python).

Uso:
    python3 tests/run.py            # tudo
    python3 tests/run.py --lua dat  # apenas a suíte lua que contenha "dat"
    python3 tests/run.py --python   # apenas os testes python
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTS = os.path.join(REPO, "tests")
GAME_DIR = os.path.join(TESTS, "tmp", "game")


def run_lua(filter_name: str | None) -> int:
    try:
        import lupa
    except ImportError:  # pragma: no cover
        print("!! lupa nao instalado. Rode: pip install lupa")
        return 2

    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    paths = ";".join(
        [
            os.path.join(REPO, "moonloader", "lib", "?.lua"),
            os.path.join(REPO, "moonloader", "lib", "?", "init.lua"),
            os.path.join(TESTS, "lua", "?.lua"),
            os.path.join(REPO, "?.lua"),
        ]
    )
    lua.execute(f'package.path = [[{paths};]] .. package.path')
    os.environ["VPE_TEST_GAME_DIR"] = GAME_DIR
    os.environ["VPE_TEST_FILTER"] = filter_name or ""
    lua.execute("VPE_TEST_GAME_DIR = [[%s]]" % GAME_DIR)
    lua.execute("VPE_TEST_LUA_DIR = [[%s]]" % os.path.join(TESTS, "lua"))

    runner = os.path.join(TESTS, "lua", "run.lua")
    with open(runner, "r", encoding="utf-8") as fh:
        source = fh.read()

    chunk = lua.eval("function(src, name) return assert(load(src, name)) end")(source, "@run.lua")
    result = chunk()
    summary = lua.globals().TEST_RESULT
    if summary is None:
        print("!! a suíte Lua não retornou resultado")
        return 1
    failed = int(summary.failed)
    return 1 if failed else 0


def run_python() -> int:
    loader = unittest.TestLoader()
    start = os.path.join(TESTS, "python")
    suite = loader.discover(start, pattern="test_*.py", top_level_dir=REPO)
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    return 0 if result.wasSuccessful() else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua", nargs="?", const="", default=None, help="roda apenas os testes Lua (filtro opcional)")
    parser.add_argument("--python", action="store_true", help="roda apenas os testes Python")
    args = parser.parse_args()

    os.makedirs(GAME_DIR, exist_ok=True)
    status = 0

    if args.lua is not None or not args.python:
        print("== Suíte Lua (MoonLoader simulado) ==")
        status |= run_lua(args.lua if args.lua else None)

    if args.python or args.lua is None:
        print("\n== Suíte Python (implementação de referência) ==")
        status |= run_python()

    print("\nResultado final:", "OK" if status == 0 else "FALHOU")
    return status


if __name__ == "__main__":
    sys.exit(main())
