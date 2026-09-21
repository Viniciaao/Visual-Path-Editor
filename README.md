# Visual Path Editor (Lua)

Editor **visual** dos path nodes do GTA San Andreas (arquivos `nodes*.dat`), escrito em
Lua para MoonLoader. É uma reescrita do CLEO *"SA WIP Visual Path Editor 1.0"*
(Lightvelox), mantendo a ideia do editor no jogo mas resolvendo os dois problemas do
original: **não gravava os `nodes*.dat` corretamente** e era difícil de usar.

* Interface em **Português e Inglês** (troca no menu, aba *Configurações*).
* **Validação antes de gravar**: se algo estiver errado, o mod avisa e **não salva**.
* Gravação em pasta do **ModLoader** — o `gta3.img` original **nunca é alterado**.
* Edição pelo **painel numérico** e **direto no mundo** (arrastando com o mouse).

---

## 1. Requisitos

| Item | Versão | Observação |
|---|---|---|
| MoonLoader | 0.26.x (alvo: **v0.26.5 beta**) | usa `render*`, `io`, `require`, eventos |
| Moon ImGui | **1.1.5** | necessário para o menu (sem ele o mod roda, mas sem painel) |
| ModLoader | 0.3.x | para os arquivos sobrescreverem os do jogo |
| MoonAdditions | opcional | o mod **não depende** dele |
| mimgui | opcional | se estiver instalado e não houver Moon ImGui, é usado como reserva |

Nenhuma biblioteca externa de terceiros é necessária: tudo que o mod usa (bit, strings,
arquivos, render) está na própria API do MoonLoader.

---

## 2. Instalação

1. Copie a pasta `moonloader/` deste projeto para dentro da pasta do GTA San Andreas,
   juntando com a que já existe:
   ```
   GTA San Andreas/
     moonloader/
       VisualPathEditor.lua          <- script do mod
       lib/vpe/*.lua                 <- modulos
       lib/vpe/lang/{pt,en}.lua      <- traducoes
   ```
2. Entre no jogo. O script carrega sozinho (`moonloader/VisualPathEditor.lua`).
3. O menu abre com **F7**. Um arquivo de configuração é criado em
   `moonloader/config/VisualPathEditor.ini` no primeiro uso.

> Não é preciso editar `gta3.img`, nem usar `loader.txt`.

---

## 3. Onde os arquivos são gravados

Quando você salva, o mod escreve **três cópias**:

| Pasta | Para que serve |
|---|---|
| `modloader/VisualPath/gta3.img/nodesN.dat` | **é daqui que o jogo carrega** (override solto do ModLoader dentro de uma pasta chamada `gta3.img`) |
| `modloader/VisualPath/export/nodesN.dat` | cópia de conferência |
| `modloader/VisualPath/backup/nodesN.dat` | backup do arquivo original, feito **antes** da primeira gravação |

* Se o arquivo **não existir** em nenhum mod, o mod lê o original de `models/gta3.img`.
* Se existir um override em outro mod (pasta do ModLoader), ele tem prioridade na leitura
  e é mostrado na aba *Área*.
* O `gta3.img` só é escrito se você ligar a opção `tambem_gta3img_direto` no INI
  (desligada por padrão).
* Ao salvar, o mod limpa o cache do ModLoader (opcional, ligado por padrão) para o jogo
  enxergar o arquivo novo sem reiniciar.

---

## 4. Como usar

### Teclas (todas configuráveis no INI / aba Configurações)

| Tecla | Ação |
|---|---|
| **F7** | abre/fecha o painel |
| **F8** | liga/desliga o desenho dos nodes no mundo |
| **F9** | valida as áreas carregadas |
| **F5** | salva (com validação) |
| **F6** | recarrega as áreas do disco |
| **Ctrl+Z / Ctrl+Y** | desfazer / refazer (até 60 passos) |
| **Insert** | cria um node na mira da câmera |
| **Delete** | apaga o node selecionado (pede confirmação se ele tiver links) |
| **Tab** | passa para o próximo node próximo |
| **G** | vai (teleporta) para o node selecionado |
| **P** | coloca o node selecionado no jogador |
| **L** | coloca o node selecionado na mira |
| **K** | cola o node no chão |
| **Ctrl+L** | marca a origem do link |
| **Enter** | cria o link da origem marcada até o node selecionado |

**Mouse** (com o painel fechado, evita conflito com o ImGui):
* **botão direito** em um node = seleciona;
* **botão esquerdo arrastando** sobre o node selecionado = move no plano X/Y;
* a altura (Z) é editada pelos botões do painel, pelo teclado numérico ou pelas teclas
  **K/P/L**; `passo_fino` (Ctrl) = 0.125, normal = 1.0, `passo_grosso` (Shift) = 8.0.

### Abas do painel

| Aba | O que faz |
|---|---|
| **Editor** | lista e edita o node selecionado: coordenadas, tipo (veículo/pedestre/barco), largura, flood fill, todas as flags, links e o navi node do link |
| **Navi** | cria/edita/remove navi nodes: alvo, direção, largura, faixas, semáforo, trem; gerar em lote e remover os inúteis |
| **Criar/Remover** | escolhe o tipo, cria na mira/no jogador, liga/desliga espelhamento de links, bloqueio manual de nodes, apagar node |
| **Área** | lista as 64 áreas (quantos nodes/links/navis cada uma), carrega/descarrega, mostra de onde o arquivo veio |
| **Salvar** | resumo do que mudou, validação, salvar / salvar como / reverter / restaurar backup |
| **Câmera** | teleporte e ajustes de visualização (distância, cores, mapa) |
| **Configurações** | idioma, teclas, render, passos, espelhamento, restaurar padrões |
| **Histórico** | log do mod (também vai para `moonloader/VisualPathEditor.log`) |
| **Ajuda** | referência rápida das teclas e do formato |

---

## 5. Validação (o mod avisa em vez de gravar errado)

Antes de qualquer gravação o mod valida as áreas alteradas — o salvamento **para** se
houver erro. A validação também roda sozinha a cada 1,5 s enquanto você edita, e o
resultado aparece no HUD/painel e no log.

**Erros (bloqueiam o salvamento)**

* coordenada fora do intervalo do formato (`int16 / 8`) ou fora da área do arquivo;
* mais de 15 links em um node;
* links/navis apontando para área, node ou navi que **não existe** (inclusive IDs -1 ou
  fora do arquivo);
* header inconsistente (contagem de veículos maior que a de nodes, arquivo truncado);
* violações de limite do formato (mais de 65535 nodes/links, mais de 1024 navi nodes).

**Avisos (pedem confirmação)**

* link sem o inverso (mão única), tipo misturado (veículo ↔ pedestre);
* node isolado, dois nodes na mesma posição, comprimento de link errado;
* navi com direção/faixas/altura suspeitas, navi link em node de pedestre;
* `nodesN.dat` faltando na área vizinha, probabilidade de spawn zero.

**Informações**: node com um único link (beco sem saída), alvo ainda não carregado etc.

Muitos erros e avisos têm **correção automática**: o painel mostra o botão de corrigir e
a aba *Salvar* aplica todas de uma vez (revalidando a cada passada, então nada é corrigido
com índice velho).

---

## 6. Formato e limites (para referência)

* 64 áreas (`nodes0.dat` .. `nodes63.dat`), grade de 750×750 unidades, começando no canto
  sudoeste (-3000, -3000), em ordem de linha (8×8).
* Cabeçalho de 20 bytes: `nodeCount`, `vehCount`, `pedCount`, `naviCount`, `linkCount`.
* Node: 28 bytes (XYZ `int16/8`, heurística `0x7FFE`, `linkID`, `areaID`, `nodeID`,
  `pathWidth`, `floodFill`, flags de 32 bits — bits 0–3 = quantidade de links).
* Navi node: 14 bytes. Link: 4 bytes. Preenchimento: 768 bytes. Navi link: 2 bytes
  (10 bits de ID + 6 bits de área). Comprimentos: 1 byte. Interseções: 1 byte.
* Cauda de 192 bytes: os bytes originais são **preservados** ao salvar.
* Máximo de 15 links por node, 65535 nodes/links e 1024 navi nodes por área.

O mod nunca reordena nem renomeia área/node/link por conta própria: ao criar/apagar um
node, os `NodeID`, os `linkID`, os links que apontavam para ele e os navi nodes
associados são atualizados de forma coerente (inclusive links entre áreas diferentes).

---

## 7. Estrutura do repositório

```
moonloader/VisualPathEditor.lua      script de entrada (loop principal, eventos)
moonloader/lib/vpe/
  app.lua        estado do editor: carregar/editar/validar/salvar, undo, teclas
  ui.lua         painel Moon ImGui (abas, widgets, modal de confirmacao, status)
  model.lua      modelo de edicao (nodes, navis, links, undo/redo, selecao)
  dat.lua        leitura e escrita dos nodes*.dat (formato binario)
  validate.lua   motor de validacao + correcoes automaticas
  sources.lua    de onde ler e para onde gravar (modloader > gta3.img), backup
  img.lua        leitor/escritor do gta3.img (VER2)
  render.lua     desenho no mundo, HUD e mapa
  gizmo.lua      arrasto do node com o mouse
  geometry.lua   grade das 64 areas, raycast, solo/agua
  config.lua     INI (moonloader/config/VisualPathEditor.ini)
  i18n.lua       traducao (pt/en)
  lang/pt.lua    dicionario portugues (canonico)
  lang/en.lua    dicionario ingles
  fs.lua         arquivos/pastas (com fallback para io do Lua)
  util.lua       utilidades (bits, cores, coordenadas, arredondamento)
  log.lua        log em arquivo
  selftest.lua   autoteste (round-trip byte a byte, ambiente, validacao)
tests/           suite de testes fora do jogo (ver secao 8)
```

---

## 8. Testes

Os testes rodam **fora do jogo**, com um MoonLoader simulado (mock do ImGui, do render,
das teclas e de uma pasta de jogo real no disco):

```bash
python3 tests/run.py                 # tudo (Lua + Python)
python3 tests/run.py --lua           # somente a suite Lua
python3 tests/run.py --lua dat       # filtra uma suite
python3 tests/run.py --python        # so a implementacao de referencia em Python
```

O que a suíte cobre:

* **round-trip byte a byte** de arquivos `nodes*.dat` (parse + serialize = original);
* o mesmo formato implementado **de novo em Python** e comparado byte a byte com o Lua;
* edição (criar/apagar node, link mão única, navi em lote, bloqueio, undo/redo);
* gravação no ModLoader, backup, reverter e `gta3.img` intocado;
* validação e correções automáticas;
* UI (todas as abas desenham, botões respondem) e o script de entrada
  (compila, registra `main`, e o loop roda vários quadros sem erro);
* traduções: toda chave usada no código existe em pt **e** en.

Autoteste dentro do jogo: no console do MoonLoader, chame `showSelfTest()` — ele confere
ambiente, round-trip das áreas carregadas e validação, e escreve o resultado no log.

---

## 9. Problemas comuns

| Sintoma | O que fazer |
|---|---|
| Menu não abre | Moon ImGui 1.1.5 instalado? Veja o log em `moonloader/VisualPathEditor.log` |
| "não carregou a área N" | Não existe `nodesN.dat` no modloader **nem** no `gta3.img`; importe pela aba *Área* |
| Alterações não aparecem no jogo | Saia do jogo e volte (ou desligue o ModLoader e ligue), o jogo só lê os paths no carregamento |
| Salvamento bloqueado | Veja os erros na aba *Salvar*: corrija os marcados ou use "corrigir automaticamente" |
| Arquivo salvo com avisos | O mod pergunta antes; confirme apenas se tiver certeza do que está fazendo |
| Quero voltar atrás | Aba *Salvar* → **reverter** (tira o override do modloader) e **restaurar backup** |

---

## 10. Língua / Language

Veja a seção em inglês abaixo. O idioma é trocado na aba **Configurações** (idioma
`pt`/`en`) e fica salvo no INI.

### English

Visual editor for GTA San Andreas path nodes (`nodes*.dat`), written in Lua for
MoonLoader; a rewrite of Lightvelox's CLEO *"SA WIP Visual Path Editor 1.0"* that fixes
its broken `nodes*.dat` writing and its usability problems.

* GUI in **Portuguese and English**, switchable in the settings tab.
* **Validation before saving**: invalid edits are reported and the save is aborted.
* Writes into a **ModLoader folder** — the original `gta3.img` is never modified
  (files are also copied to `export/` and the previous file is kept in `backup/`).
* Both editing modes: **numeric panel** and **in-world mouse dragging**.
* Correct 64-area / 750×750 grid handling, coherent Area/Node/Link IDs after
  add/delete, cross-area links, navi nodes, undo/redo, node locking and automatic
  fixes; unknown bytes (192-byte tail) are preserved.

Install: copy the `moonloader/` folder into your GTA San Andreas directory. Requires
MoonLoader 0.26.x (target 0.26.5 beta), Moon ImGui 1.1.5 and ModLoader. Press **F7**
in game to open the panel. Run `python3 tests/run.py` to execute the offline test suite.

---

## Créditos

* Inspirado em *SA WIP Visual Path Editor 1.0* de **Lightvelox** (modo de edição no jogo).
* Formato dos `nodes*.dat` documentado no GTAMods Wiki / Grand Theft Wiki.
* Feito para MoonLoader (Lua) com Moon ImGui.
