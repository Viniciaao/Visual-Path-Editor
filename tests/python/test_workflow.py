"""Fluxo completo, de ponta a ponta: o mod Lua edita uma area de verdade e grava
no ModLoader; aqui o arquivo gravado e conferido com a implementacao de
referencia em Python (nada do Lua participa da verificacao).

Cobre o caminho que o usuario faz no jogo: carregar a area, mover/criar nodes,
criar link, gerar navi, validar e salvar - e depois prova que o arquivo gravado:
  * tem o tamanho exato do formato;
  * tem o cabecalho coerente;
  * so aponta para nodes/navis que existem;
  * preservou a cauda e os bytes desconhecidos;
  * nao encostou no gta3.img do jogo.
"""

from __future__ import annotations

import os
import shutil
import unittest

from tests.python import lua_support as support
from tests.python import vpe_reference as ref

REPO = support.REPO
GAME = os.path.join(REPO, "tests", "tmp", "game")
ROOT = os.path.join(GAME, "pysuite")
ML = os.path.join(ROOT, "modloader")
MOD = os.path.join(ML, "VisualPath")
OVERRIDE = os.path.join(MOD, "gta3.img")
EXPORT = os.path.join(MOD, "export")
BACKUP = os.path.join(MOD, "backup")
IMG_FOLDER = os.path.join(ROOT, "models")

LUA_SETUP = r"""
local mock = require 'support.mock_moonloader'
mock.install()
"""

LUA_CREATE_IMG = r"""
local img = require 'vpe.img'
local created, err = img.create([[%(imgfolder)s/gta3.img]], {
	{ name = 'nodes15.dat', data = VPE_FIXTURE },
	{ name = 'veiculos.dat', data = string.rep('\\0', 4096) },
})
if not created then return 'falha ao criar o gta3.img: ' .. tostring(err) end
return true
"""

LUA_WORKFLOW = r"""
local fs = require 'vpe.fs'
local util = require 'vpe.util'
local config = require 'vpe.config'
local dat = require 'vpe.dat'
local img = require 'vpe.img'
local appModule = require 'vpe.app'
local selftest = require 'vpe.selftest'
local i18n = require 'vpe.i18n'
i18n.setLang('pt')

local ROOT = [[%(root)s]]
local GAME = [[%(game)s]]
local ML = [[%(ml)s]]
local OVERRIDE = [[%(override)s]]
local IMG_FOLDER = [[%(imgfolder)s]]

fs._gameDir = GAME
local settings = util.deepcopy(config.defaults)
settings.geral.carregar_vizinhas = false
settings.salvar.pasta_export = ROOT .. '/modloader/VisualPath/export'
settings.salvar.pasta_img = ROOT .. '/modloader/VisualPath/gta3.img'
settings.salvar.pasta_backup = ROOT .. '/modloader/VisualPath/backup'

local A = appModule.new({ gameDir = GAME, modloaderDir = ML, settings = settings, withUi = false, autoload = false })
A:init()
A.originals = {}
-- a imagem do "jogo" deste cenario (relativa a pasta do jogo)
A.sources.imgFiles = { [[%(imgrel)s]] }
A.sources.scanned = false

local out = {}

-- 1) carrega a area 15 do gta3.img (nao existe override ainda)
out.imgSource = tostring(A.sources:scan() and A.sources:info(15).source)
local ok, err = A:loadArea(15)
out.loaded = ok == true
out.loadErrorText = tostring(err)
out.loadError = tostring(err)
local loadedArea = A.project:area(15)
out.nodesBefore = loadedArea and #loadedArea.nodes or -1
out.triangleRoundTrip = loadedArea and (function()
	local report = selftest.roundTrip(A, { 15 })
	return report.failed
end)() or -1

-- 2) edita: move o node 1, cria um node novo e liga no node 2
A:selectNode(15, 1)
A:nudge(4, -2, 0)
A.linkMode = 'manual'
local created, index = A:createNode('veh', 2520.0, -1684.0, 10.0)
out.created = created == true and index or 0
if created then
	A:selectNode(15, 2)
	A:markLinkSource()
	A:selectNode(15, index)
	A:createLink()
end

-- 3) gera os navi nodes que faltam
out.navisCreated = A:generateMissingNavis(15)

-- 4) valida e salva
local report = A:validate({ inGame = false, silent = true })
out.errors = report.errors
out.warns = report.warns
local result = A:save({ force = false, confirmed = true })
out.saved = result.ok == true
out.reason = tostring(result.reason)
out.written = result.mainPath or ''

-- 5) le de volta do disco pelo mod e confere
A.originals[15] = nil
local reloaded = A:loadArea(15, { force = true })
out.reloaded = reloaded == true
out.nodesAfter = #A.project:area(15).nodes
out.byteIdentical = (function()
	local bytes = fs.readAll(OVERRIDE .. '/nodes15.dat')
	local area = dat.parse(bytes, 15)
	local again = area and dat.serialize(area)
	return bytes ~= nil and again == bytes
end)()

out.gameImgExists = fs.exists(IMG_FOLDER .. '/gta3.img')
out.overrideExists = fs.exists(OVERRIDE .. '/nodes15.dat')
out.exportExists = fs.exists(ROOT .. '/modloader/VisualPath/export/nodes15.dat')
out.backupExists = fs.exists(ROOT .. '/modloader/VisualPath/backup/nodes15.dat')
return out
"""


def lua_dict_to_py(value):
    if value is None or isinstance(value, (str, bytes, int, float, bool)):
        return value
    try:
        return {k: lua_dict_to_py(v) for k, v in value.items()}
    except AttributeError:
        return value


class WorkflowTests(unittest.TestCase):
    """Edita e grava pelo Lua; confere o resultado independentemente."""

    @classmethod
    def setUpClass(cls):
        # cenário: existe a imagem completa do jogo (com nodes15.dat) e ainda
        # nao existe nenhum override no modloader.
        shutil.rmtree(ROOT, ignore_errors=True)
        os.makedirs(IMG_FOLDER, exist_ok=True)
        cls.fixture = ref.serialize(ref.sample_area())

        cls.lua = support.new_runtime()
        cls.lua.execute("package.path = [[%s/tests/lua/?.lua;]] .. package.path" % REPO)
        cls.lua.execute(LUA_SETUP)
        cls.lua.globals()["VPE_FIXTURE"] = cls.fixture
        created = cls.lua.execute(LUA_CREATE_IMG % {"game": GAME, "imgfolder": IMG_FOLDER})
        assert created is True, created

        with open(os.path.join(IMG_FOLDER, "gta3.img"), "rb") as fh:
            cls.img_before = fh.read()

        cls.result = lua_dict_to_py(cls.lua.execute(LUA_WORKFLOW % {
            "root": ROOT, "game": GAME, "ml": ML,
            "override": OVERRIDE, "imgfolder": IMG_FOLDER,
            "imgrel": "pysuite/models/gta3.img",
        }))
        cls.saved_path = os.path.join(OVERRIDE, "nodes15.dat")
        cls.saved = open(cls.saved_path, "rb").read()
        cls.area = ref.parse(cls.saved, 15)

    def test_o_workflow_lua_correu_como_esperado(self):
        self.assertEqual(self.result["loadError"], "nil", "a area veio do gta3.img")
        self.assertTrue(self.result["loaded"], "carregou a area 15")
        self.assertEqual(self.result["nodesBefore"], 4)
        self.assertEqual(self.result["triangleRoundTrip"], 0, "round-trip antes de editar")
        self.assertEqual(self.result["created"], 5, "criou o node novo no fim dos veiculos")
        self.assertEqual(self.result["navisCreated"], 3, "gerou os navis que faltavam")
        self.assertEqual(self.result["errors"], 0, "sem erros de validacao")
        self.assertTrue(self.result["saved"], "salvou: %s (%s)" % (self.result["saved"], self.result["reason"]))
        self.assertTrue(self.result["reloaded"])
        self.assertTrue(self.result["byteIdentical"], "o Lua rele e reescreve os mesmos bytes")

    def test_gravou_nos_tres_lugares(self):
        self.assertTrue(self.result["overrideExists"], "override do modloader")
        self.assertTrue(self.result["exportExists"], "copia de exportacao")
        self.assertTrue(self.result["backupExists"], "backup do original")
        self.assertTrue(os.path.exists(self.saved_path))

    def test_o_gta3_img_do_jogo_nao_foi_tocado(self):
        with open(os.path.join(IMG_FOLDER, "gta3.img"), "rb") as fh:
            self.assertEqual(fh.read(), self.img_before)

    def test_o_arquivo_gravado_tem_o_tamanho_do_formato(self):
        self.assertEqual(len(self.saved), ref.expected_size(5, 4, 8))

    def test_cabecalho_coerente(self):
        import struct

        node_count, veh, ped, navi, links = struct.unpack_from("<5I", self.saved, 0)
        self.assertEqual(node_count, 5)
        self.assertEqual(veh, 5, "todos os nodes criados sao de veiculo")
        self.assertEqual(ped, 0)
        self.assertEqual(navi, 4)
        self.assertEqual(links, 8, "6 links do comeco + 2 do node novo")

    def test_todos_os_links_apontam_para_nodes_que_existem(self):
        for node in self.area["nodes"]:
            for link in node["links"]:
                self.assertLess(link["node"], len(self.area["nodes"]),
                                "link para node inexistente: %s" % link)

    def test_links_reciprocos(self):
        for index, node in enumerate(self.area["nodes"]):
            for link in node["links"]:
                target = self.area["nodes"][link["node"]]
                back = [l for l in target["links"] if l["node"] == index]
                self.assertTrue(back, "node %d -> %d sem o link de volta" % (index, link["node"]))

    def test_flags_guardam_a_quantidade_de_links(self):
        for index, node in enumerate(self.area["nodes"]):
            self.assertEqual(node["flags"] & 0x0F, len(node["links"]),
                             "node %d: flags dizem outra coisa" % index)

    def test_navi_links_apontam_para_navis_existentes(self):
        self.assertEqual(len(self.area["navis"]), 4)
        for node in self.area["nodes"]:
            for link in node["links"]:
                if link["naviArea"] or link["naviID"]:
                    self.assertEqual(link["naviArea"], 15)
                    self.assertLess(link["naviID"], len(self.area["navis"]))

    def test_o_node_movido_ficou_onde_foi_pedido(self):
        self.assertAlmostEqual(self.area["nodes"][0]["x"], 2499.0, places=3)
        self.assertAlmostEqual(self.area["nodes"][0]["y"], -1686.0, places=3)
        self.assertAlmostEqual(self.area["nodes"][4]["x"], 2520.0, places=3)

    def test_a_cauda_desconhecida_foi_preservada(self):
        original = ref.parse(self.fixture, 15)
        self.assertEqual(self.area["tail"], original["tail"], "bytes desconhecidos no fim do arquivo")
        self.assertEqual(self.area["filler"], original["filler"])

    def test_comprimentos_recalculados_com_o_formato_certo(self):
        for node in self.area["nodes"]:
            for index, link in enumerate(node["links"]):
                self.assertGreaterEqual(link["length"], 0)
                self.assertLessEqual(link["length"], 255)


if __name__ == "__main__":
    unittest.main()
