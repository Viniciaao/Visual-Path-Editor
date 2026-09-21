"""Implementacao de REFERENCIA do formato nodes*.dat, independente do Lua.

Serve para conferir, byte a byte, se o codec em `moonloader/lib/vpe/dat.lua`
escreve exatamente o que o formato manda. Se as duas implementacoes concordarem
em arquivos de teste, erros de deslocamento/ordem de secao ficam bem improvaveis.

Layout (arquivos nodes0.dat .. nodes63.dat, 750x750 unidades cada):

    cabecalho (20 bytes)  u32 nodeCount, vehCount, pedCount, naviCount, linkCount
    secao 1  28 bytes     por node: mem1 u32, mem2 u32, x/y/z i16 (coord * 8),
                          heuristic u16 (0x7FFE), linkID u16, areaID u16,
                          nodeID u16, pathWidth u8, floodFill u8, flags u32
    secao 2  14 bytes     por navi: x/y i16, areaID u16, nodeID u16,
                          dirX i8, dirY i8, flags u32
    secao 3   4 bytes     por link: areaID u16, nodeID u16
    secao 4   768 bytes   preenchimento padrao (0xFF 0xFF 0x00 0x00) * 192
    secao 5   2 bytes     por link: naviID (10 bits) | naviArea (6 bits)
    secao 6   1 byte      por link: comprimento em unidades (0..255)
    secao 7   1 byte      por link: flags de interseccao
    cauda     192 bytes   dados desconhecidos (preservados do arquivo original)

Os bits 0-3 das flags de node guardam a QUANTIDADE de links do node; os links
ficam em sequencia a partir de `linkID`.
"""

from __future__ import annotations

import math
import struct

HEADER_SIZE = 20
NODE_SIZE = 28
NAVI_SIZE = 14
LINK_SIZE = 4
FILLER_SIZE = 768
TAIL_SIZE = 192
INTERSECTION_SIZE = 1

HEURISTIC_COST = 0x7FFE
MEM_ADDRESS_DEFAULT = 0x01A7FF08
DEFAULT_FILLER = b"\xff\xff\x00\x00" * 192
MAX_LINKS_PER_NODE = 15
LINK_COUNT_BITS = (0, 4)


def expected_size(node_count: int, navi_count: int, link_count: int) -> int:
    return (
        HEADER_SIZE
        + NODE_SIZE * node_count
        + NAVI_SIZE * navi_count
        + LINK_SIZE * link_count
        + FILLER_SIZE
        + 2 * link_count
        + link_count
        + INTERSECTION_SIZE * link_count
        + TAIL_SIZE
    )


def round_half_away(value: float) -> int:
    """Igual ao util.round do Lua (longe do zero)."""
    return int(math.floor(value + 0.5)) if value >= 0 else int(math.ceil(value - 0.5))


def coord_to_int(value: float) -> int:
    return round_half_away(float(value) * 8)


def coord_from_int(value: int) -> float:
    return value / 8.0


def pack_navi_link(area: int, navi_id: int) -> int:
    return ((int(area) & 0x3F) << 10) | (int(navi_id) & 0x3FF)


def unpack_navi_link(raw: int) -> tuple[int, int]:
    return raw & 0x3FF, (raw >> 10) & 0x3F


def link_count(node: dict) -> int:
    return len(node.get("links") or [])


def node_flags(node: dict) -> int:
    first, count = LINK_COUNT_BITS
    flags = int(node.get("flags") or 0)
    mask = ((1 << count) - 1) << first
    return (flags & ~mask) | ((link_count(node) & ((1 << count) - 1)) << first)


def node_type(area: dict, index: int) -> str:
    """index 1-based, como no Lua."""
    if index > int(area.get("vehCount") or 0):
        return "ped"
    node = area["nodes"][index - 1]
    return "boat" if (int(node.get("flags") or 0) >> 7) & 1 == 1 else "veh"


def total_links(area: dict) -> int:
    return sum(link_count(n) for n in area["nodes"])


def serialize(area: dict) -> bytes:
    nodes = area["nodes"]
    navis = area.get("navis") or []
    node_count = len(nodes)
    navi_count = len(navis)
    n_links = total_links(area)
    if node_count > 0xFFFF:
        raise ValueError("nodes demais")
    if navi_count > 1024:
        raise ValueError("navi nodes demais")
    if n_links > 0xFFFF:
        raise ValueError("links demais")
    for index, node in enumerate(nodes, 1):
        if link_count(node) > MAX_LINKS_PER_NODE:
            raise ValueError("node %d tem links demais" % (index - 1))

    out = bytearray()
    out += struct.pack("<5I", node_count, int(area.get("vehCount") or 0),
                       node_count - int(area.get("vehCount") or 0), navi_count, n_links)

    link_id = 0
    for index, node in enumerate(nodes, 1):
        out += struct.pack(
            "<IIhhhHHHHBBI",
            int(node.get("mem1") or MEM_ADDRESS_DEFAULT),
            int(node.get("mem2") or 0),
            coord_to_int(node.get("x") or 0),
            coord_to_int(node.get("y") or 0),
            coord_to_int(node.get("z") or 0),
            int(node.get("heuristic") or HEURISTIC_COST),
            link_id,
            int(area.get("id") or 0),
            index - 1,
            int(node.get("pathWidth") or 0) & 0xFF,
            int(node.get("floodFill") or 0) & 0xFF,
            node_flags(node),
        )
        link_id += link_count(node)

    for navi in navis:
        out += struct.pack(
            "<hhHHbbI",
            coord_to_int(navi.get("x") or 0),
            coord_to_int(navi.get("y") or 0),
            int(navi.get("areaID") or 0),
            int(navi.get("nodeID") or 0),
            int(navi.get("dirX") or 0),
            int(navi.get("dirY") or 0),
            int(navi.get("flags") or 0),
        )

    links = [link for node in nodes for link in (node.get("links") or [])]
    for link in links:
        out += struct.pack("<HH", int(link.get("area") or 0), int(link.get("node") or 0))

    filler = area.get("filler")
    if not isinstance(filler, (bytes, bytearray)) or len(filler) != FILLER_SIZE:
        filler = DEFAULT_FILLER
    out += filler

    for link in links:
        out += struct.pack("<H", pack_navi_link(link.get("naviArea") or 0, link.get("naviID") or 0))

    for link in links:
        out += bytes([clamp(round_half_away(link.get("length") or 0), 0, 255)])

    intersections = area.get("intersections")
    if not isinstance(intersections, (bytes, bytearray)):
        intersections = b""
    intersections = bytes(intersections[:n_links]).ljust(n_links, b"\x00")
    out += intersections

    tail = area.get("tail")
    if not isinstance(tail, (bytes, bytearray)):
        tail = b""
    out += bytes(tail[:TAIL_SIZE]).ljust(TAIL_SIZE, b"\x00")

    return bytes(out)


def clamp(value: int, low: int, high: int) -> int:
    return low if value < low else (high if value > high else value)


def parse(data: bytes, area_id: int = 0) -> dict:
    if len(data) < HEADER_SIZE:
        raise ValueError("arquivo curto demais: %d bytes" % len(data))
    node_count, veh_count, ped_count, navi_count, link_count = struct.unpack_from("<5I", data, 0)

    def padded(offset: int, size: int) -> bytes:
        chunk = data[offset:offset + size]
        return chunk.ljust(size, b"\x00")

    area = {
        "id": area_id,
        "vehCount": veh_count,
        "headerPedCount": ped_count,
        "nodes": [],
        "navis": [],
        "filler": b"",
        "tail": b"",
        "intersections": b"",
    }

    base = HEADER_SIZE
    for index in range(node_count):
        p = base + index * NODE_SIZE
        (mem1, mem2, x, y, z, heuristic, link_id, node_area, node_id,
         path_width, flood_fill, flags) = struct.unpack_from("<IIhhhHHHHBBI", padded(p, NODE_SIZE), 0)
        area["nodes"].append({
            "mem1": mem1, "mem2": mem2,
            "x": coord_from_int(x), "y": coord_from_int(y), "z": coord_from_int(z),
            "heuristic": heuristic,
            "linkID": link_id, "areaID": node_area, "nodeID": node_id,
            "pathWidth": path_width, "floodFill": flood_fill, "flags": flags,
            "links": [],
        })

    navi_base = base + NODE_SIZE * node_count
    for index in range(navi_count):
        p = navi_base + index * NAVI_SIZE
        x, y, navi_area, navi_node, dir_x, dir_y, flags = struct.unpack_from("<hhHHbbI", padded(p, NAVI_SIZE), 0)
        area["navis"].append({
            "x": coord_from_int(x), "y": coord_from_int(y),
            "areaID": navi_area, "nodeID": navi_node,
            "dirX": dir_x, "dirY": dir_y, "flags": flags,
        })

    links_base = navi_base + NAVI_SIZE * navi_count
    links = []
    for index in range(link_count):
        p = links_base + index * LINK_SIZE
        link_area, link_node = struct.unpack_from("<HH", padded(p, LINK_SIZE), 0)
        links.append({"area": link_area, "node": link_node})

    navi_links_base = links_base + LINK_SIZE * link_count + FILLER_SIZE
    for index, link in enumerate(links):
        p = navi_links_base + index * 2
        navi_id, navi_area = unpack_navi_link(struct.unpack_from("<H", padded(p, 2), 0)[0])
        link["naviID"] = navi_id
        link["naviArea"] = navi_area

    lengths_base = navi_links_base + 2 * link_count
    for index, link in enumerate(links):
        link["length"] = padded(lengths_base + index, 1)[0]

    area["filler"] = padded(links_base + LINK_SIZE * link_count, FILLER_SIZE)
    area["intersections"] = padded(lengths_base + link_count, link_count)
    area["tail"] = padded(lengths_base + link_count + INTERSECTION_SIZE * link_count, TAIL_SIZE)

    # distribui os links pelos nodes na mesma ordem em que foram escritos
    cursor = 0
    for node in area["nodes"]:
        count = node["flags"] & 0x0F
        node["links"] = [dict(links[cursor + i]) for i in range(count) if cursor + i < len(links)]
        cursor += count

    return area


def sample_area() -> dict:
    """Area de teste: 4 nodes de veiculo em cadeia, 6 links e 1 navi."""

    def node(x, y, z, flags, links=None):
        return {
            "mem1": MEM_ADDRESS_DEFAULT, "mem2": 0,
            "x": x, "y": y, "z": z,
            "heuristic": HEURISTIC_COST,
            "pathWidth": 8, "floodFill": 1, "flags": flags,
            "links": list(links or []),
        }

    def link(to_index, navi_area=0, navi_id=0, length=5):
        return {"area": 15, "node": to_index, "naviArea": navi_area, "naviID": navi_id, "length": length}

    nodes = [
        node(2495.0, -1684.0, 10.0, 0x00011001, [link(1, navi_area=15, navi_id=0)]),
        node(2500.0, -1684.0, 10.0, 0x00021001, [link(0), link(2)]),
        node(2505.0, -1684.0, 10.0, 0x00021001, [link(1), link(3)]),
        node(2510.0, -1684.0, 10.0, 0x00011001, [link(2)]),
    ]

    return {
        "id": 15,
        "vehCount": 4,
        "nodes": nodes,
        "navis": [{
            "x": 2497.5, "y": -1684.0, "areaID": 15, "nodeID": 1,
            "dirX": 100, "dirY": 0, "flags": 8 + 1 * 256 + 1 * 2048,
        }],
        "filler": DEFAULT_FILLER,
        "intersections": b"\x00" * 6,
        "tail": b"VPE!" + b"\x00" * (TAIL_SIZE - 4),
    }
