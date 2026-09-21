"""Confere o codec Lua (moonloader/lib/vpe/dat.lua) contra a implementacao de
referencia em Python: os dois tem que escrever os MESMOS bytes."""

from __future__ import annotations

import unittest

from tests.python import vpe_reference as ref
from tests.python import lua_support as support


class ReferenceFormatTests(unittest.TestCase):
    def test_expected_size_formula(self):
        self.assertEqual(ref.expected_size(0, 0, 0), 20 + 768 + 192)
        self.assertEqual(ref.expected_size(4, 1, 6), len(ref.serialize(ref.sample_area())))

    def test_round_trip_is_byte_identical(self):
        data = ref.serialize(ref.sample_area())
        again = ref.serialize(ref.parse(data, 15))
        self.assertEqual(data, again)

    def test_header_and_sections(self):
        data = ref.serialize(ref.sample_area())
        node_count, veh, ped, navi, links = __import__("struct").unpack_from("<5I", data, 0)
        self.assertEqual((node_count, veh, ped, navi, links), (4, 4, 0, 1, 6))
        # links comecam depois de nodes + navis, e o preenchimento vem depois
        links_base = ref.HEADER_SIZE + 4 * ref.NODE_SIZE + 1 * ref.NAVI_SIZE
        self.assertEqual(data[links_base + 4 * 6:links_base + 4 * 6 + 4], b"\xff\xff\x00\x00")

    def test_node_flags_store_link_count(self):
        node = {"flags": 0x00011000, "links": [{"area": 15, "node": 1}, {"area": 15, "node": 2}]}
        flags = ref.node_flags(node)
        self.assertEqual(flags & 0x0F, 2, "bits 0-3 guardam a quantidade de links")
        self.assertEqual(flags & ~0x0F, 0x00011000, "os outros bits ficam intactos")

    def test_navi_link_packing(self):
        for area, navi_id in ((15, 0), (0, 1), (63, 1023)):
            raw = ref.pack_navi_link(area, navi_id)
            self.assertEqual(ref.unpack_navi_link(raw), (navi_id, area))

    def test_tail_is_preserved(self):
        area = ref.sample_area()
        area["tail"] = b"VPE!" + b"\xab" * 188
        parsed = ref.parse(ref.serialize(area), 15)
        self.assertEqual(parsed["tail"], area["tail"])


class LuaCodecMatchesReference(unittest.TestCase):
    """Nada aqui usa o codigo Lua para decidir o resultado esperado."""

    @classmethod
    def setUpClass(cls):
        cls.lua = support.new_runtime()
        cls.dat = support.module(cls.lua, "vpe.dat")
        cls.sample = ref.sample_area()

    def lua_area(self, area=None):
        return support.to_lua(self.lua, area if area is not None else self.sample)

    def test_lua_serialize_matches_python(self):
        result = self.dat.serialize(self.lua_area())
        err = support.second(result)
        self.assertIsNone(err, "Lua recusou a area: %s" % err)
        self.assertEqual(support.as_bytes(support.first(result)), ref.serialize(self.sample))

    def test_lua_parses_python_bytes_and_rewrites_them_identically(self):
        data = ref.serialize(self.sample)
        area = support.first(self.dat.parse(data, 15))
        self.assertIsNotNone(area, "Lua nao conseguiu ler o arquivo escrito pelo Python")
        rewritten = support.first(self.dat.serialize(area))
        self.assertEqual(support.as_bytes(rewritten), data)

    def test_lua_reads_the_same_fields(self):
        data = ref.serialize(self.sample)
        area = support.first(self.dat.parse(data, 15))
        self.assertEqual(area["vehCount"], 4)
        self.assertEqual(len(area["nodes"]), 4)
        self.assertEqual(len(area["navis"]), 1)
        node = area["nodes"][1]
        self.assertAlmostEqual(node["x"], 2495.0, places=6)
        self.assertAlmostEqual(node["y"], -1684.0, places=6)
        self.assertEqual(node["pathWidth"], 8)
        self.assertEqual(len(node["links"]), 1)
        link = node["links"][1]
        self.assertEqual((link["area"], link["node"]), (15, 1))
        self.assertEqual((link["naviArea"], link["naviID"]), (15, 0))
        self.assertEqual(link["length"], 5)
        navi = area["navis"][1]
        self.assertEqual((navi["areaID"], navi["nodeID"]), (15, 1))
        self.assertEqual((navi["dirX"], navi["dirY"]), (100, 0))
        self.assertEqual(navi["flags"], 8 + 256 + 2048)

    def test_lua_expected_size_matches_reference(self):
        lua_size = self.dat.expectedSize(support.to_lua(self.lua, {
            "nodeCount": 4, "vehCount": 4, "pedCount": 0, "naviCount": 1, "linkCount": 6,
        }))
        self.assertEqual(lua_size, ref.expected_size(4, 1, 6))

    def test_lua_repairs_truncated_file(self):
        """Arquivos salvos por outras ferramentas podem vir sem as ultimas secoes."""
        data = ref.serialize(self.sample)
        truncated = data[:len(data) - 250]
        result = self.dat.parse(truncated, 15)
        area, err = support.first(result), support.second(result)
        self.assertIsNotNone(area, "Lua deveria aceitar o arquivo truncado: %s" % err)
        notes = area["notes"]
        self.assertGreaterEqual(len(notes), 1, "o parser devia anotar o tamanho estranho")
        fixed = support.as_bytes(support.first(self.dat.serialize(area)))
        self.assertEqual(len(fixed), ref.expected_size(4, 1, 6), "o arquivo salvo volta ao tamanho completo")
        # tudo o que existia antes do corte continua igual
        self.assertEqual(fixed[:ref.HEADER_SIZE + 4 * ref.NODE_SIZE + ref.NAVI_SIZE + 4 * 6], data[:ref.HEADER_SIZE + 4 * ref.NODE_SIZE + ref.NAVI_SIZE + 4 * 6])

    def test_lua_rejects_out_of_range_coordinates(self):
        area = ref.sample_area()
        area["nodes"][0]["x"] = 99999.0
        result = self.dat.serialize(self.lua_area(area))
        self.assertIsNone(support.first(result), "coordenada fora do i16 deve ser recusada")
        self.assertIsNotNone(support.second(result))


if __name__ == "__main__":
    unittest.main()
