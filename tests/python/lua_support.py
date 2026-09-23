"""Ponte entre os testes Python e os modulos Lua (via lupa)."""

from __future__ import annotations

import os

import lupa

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def new_runtime() -> "lupa.LuaRuntime":
    # latin-1: os arquivos nodes*.dat sao binarios e o lupa nao pode tentar
    # decodificar UTF-8 (a string Lua vai e volta sem perda).
    lua = lupa.LuaRuntime(unpack_returned_tuples=True, encoding="latin-1")
    paths = ";".join(
        [
            os.path.join(REPO, "moonloader", "lib", "?.lua"),
            os.path.join(REPO, "moonloader", "lib", "?", "init.lua"),
        ]
    )
    lua.execute("package.path = [[%s;]] .. package.path" % paths)
    return lua


def module(lua: "lupa.LuaRuntime", name: str):
    # no Lua 5.4+ require devolve (modulo, loaderdata): com unpack_returned_tuples
    # isso vira uma tupla no Python.
    result = lua.eval("(function(n) return require(n) end)")(name)
    return result[0] if isinstance(result, tuple) else result


def to_lua(lua: "lupa.LuaRuntime", value):
    """Converte dict/list/tuple/bytes Python para tabelas e strings Lua."""
    if isinstance(value, dict):
        table = lua.table()
        for key, item in value.items():
            table[key] = to_lua(lua, item)
        return table
    if isinstance(value, (list, tuple)):
        table = lua.table()
        for index, item in enumerate(value, 1):
            table[index] = to_lua(lua, item)
        return table
    return value


def as_bytes(value) -> bytes:
    """Strings Lua chegam como bytes ou str (latin-1) dependendo do conteudo."""
    if value is None:
        return b""
    if isinstance(value, bytes):
        return value
    if isinstance(value, str):
        return value.encode("latin-1")
    raise TypeError("nao sei converter %r para bytes" % type(value))


def first(result):
    """lupa devolve tuplas para multiplos retornos."""
    if isinstance(result, tuple):
        return result[0] if result else None
    return result


def second(result):
    if isinstance(result, tuple):
        return result[1] if len(result) > 1 else None
    return None
