# Visual Path Editor (Lua)

Editor **visual** dos path nodes do GTA San Andreas (arquivos `nodes*.dat`), escrito em
Lua para MoonLoader. É uma reescrita do CLEO *"SA WIP Visual Path Editor 1.0"*
(Lightvelox), mantendo a ideia do editor no jogo mas resolvendo os dois problemas do
original: **não gravava os `nodes*.dat` corretamente** e era difícil de usar.

* Interface em **Português e Inglês** (troca no menu, aba *Configurações*).
* **Validação antes de gravar**: se algo estiver errado, o mod avisa e **não salva**.
* Gravação em pasta do **ModLoader** — o `gta3.img` original **nunca é alterado**.
* Edição pelo **painel numérico** e **direto no mundo** (arrastando com o mouse).
* **[TUTORIAL.md](TUTORIAL.md) — tutorial completo em português**: o que é cada tipo
  de node, como criar nodes de **carro, pedestre e barco**, navi nodes, links,
  flags, validação, salvamento e como voltar atrás.

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

> Guia passo a passo (com receitas de rua, calçada, barco, semáforo e conserto):
> **[TUTORIAL.md](TUTORIAL.md)**.

### Teclas (todas configuráveis no INI / aba Configurações)

| Tecla | Ação |
|---|---|
| **F7** | abre/fecha o painel |
| **F8** | liga/desliga o desenho dos nodes no mundo |
| **F9** | valida as áreas carregadas |
| **F10** | liga/desliga o **diagnóstico do desenho** (marcas de referência + números no log) |
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

### Tamanho do painel (escala da interface)

O ImGui desenha com fonte de ~13 px, que é pequena para muita gente. A **1.0.7**
nasce com **escala 1.35** e dá três controles:

| Onde | Como |
|---|---|
| Topo do painel | botões **A-** / **A+** (0,1 por clique) |
| *Configurações → Geral* | slider **Escala da interface** (0,60 a 2,50) |
| INI | `[geral] escala_ui = 1.35` |

A escala vale na hora (fonte + tamanho da janela), fica salva no INI e, se a build
de ImGui não aceitar `FontGlobalScale`, o mod cai para `SetWindowFontScale` e avisa
no chat caso nem isso exista.

### Carregar nodes (o que ele faz, exatamente)

1. carrega a área onde o jogador está (e as vizinhas, se `carregar_vizinhas`
   estiver ligado);
2. **seleciona essa área no painel** — o título passa a mostrar `(vX.Y.Z, area N)` e
   a aba *Editor* mostra as contagens dela;
3. escreve no chat `VPE: area N carregada (M nodes) - ela esta selecionada no painel`
   (ou `ja estava carregada`, quando o auto-carregar já tinha feito o serviço).

Se nenhuma área está selecionada, a aba *Editor* lista todas as **áreas carregadas**
com as contagens, para você escolher com um clique.

### Abas do painel

| Aba | O que faz |
|---|---|
| **Editor** | lista e edita o node selecionado: coordenadas, tipo (veículo/pedestre/barco), largura, flood fill, todas as flags, links e o navi node do link |
| **Navi** | cria/edita/remove navi nodes: alvo, direção, largura, faixas, semáforo, trem; gerar em lote e remover os inúteis |
| **Criar/Remover** | escolhe o tipo do node novo, cria na mira/no jogador, modo de ligação, espelhamento de links, bloqueio manual, apagar node |
| **Área** | lista as áreas carregadas e as 64 do mundo (nodes/links/navis), carrega/descarrega, mostra a origem de cada arquivo e onde ele será gravado, cria **área vazia**, e por área: **Salvar alterações**, **Exportar**, **Reverter (tirar do ModLoader)** e **Restaurar backup** |
| **Salvar** | diferenças por arquivo, resumo da validação, **Validar de novo**, **Corrigir tudo**, **Salvar alterações**, **Salvar mesmo assim** e **Limpar cache do ModLoader** |
| **Câmera** | teleporte e ajustes de visualização (distância, cores, mapa) |
| **Configurações** | idioma, **escala da interface**, teclas, render, passos, espelhamento, restaurar padrões |
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

Além disso, depois de gravar o mod **lê o arquivo de volta e compara byte a byte** com o
que mandou escrever: se o disco entregar outra coisa (gravação truncada, por exemplo), o
salvamento é reportado como falha — nunca como sucesso.

Muitos erros e avisos têm **correção automática**: o painel mostra o botão de corrigir e
a aba *Salvar* aplica todas de uma vez (revalidando a cada passada, então nada é corrigido
com índice velho).

---

## 5.1. Como o desenho no mundo funciona (e o que ajustar)

O mod desenha cada quadro, projetando as coordenadas do mundo para a tela:

* **Marcadores pequenos e discretos**: um node é um quadradinho de 3–12 px
  (`tamanho_mundo` = 1,2 m, limitado por `tamanho_minimo`/`tamanho_maximo`). O navi
  node é uma **cruz** (fica distinto dos nodes e não cobre o chão) e o node
  selecionado/sob o mouse ganha **cruz de destaque**.
* **Tamanho por distância** (`escala_por_distancia`, `tamanho_mundo`): o marcador tem
  um tamanho *em metros* e encolhe com a distância — é o que faz o desenho parecer
  parte do mundo em vez de uma camada colada na tela. Desligue para voltar ao
  tamanho fixo em pixels (`tamanho_node`).
* **Oclusão** (`oclusao`, `oclusao_raio`, `oclusao_max_por_quadro`): faz um raycast da
  câmera até o node (`isLineOfSightClear`) e **não desenha o que está atrás de
  prédio/parede**. O resultado fica em cache por 0,25 s e há um teto de raycasts por
  quadro para não pesar.
* **Links só do node escolhido** (`links_modo` = `selecionado` | `todos` | `nenhum`):
  o padrão desenha **apenas as ligações do node selecionado (ou sob o mouse)**. Antes,
  desenhar as ligações de todos os nodes fazia uma teia de linhas sobre a cidade —
  era o que deixava a tela ilegível. Use `todos` quando quiser ver a rede inteira.
* **Limites** (`distancia`, `distancia_navis`, `distancia_links`, `max_nodes`,
  `max_navis`, `max_linhas`, `largura_link`): em avenida cheia, centenas de marcadores
  viram confusão — os padrões são 120 m de alcance, 60 m para navi nodes e 250/80
  marcadores, o suficiente para editar sem poluir.
* **Dois presets** (aba *Configurações* → *Render*): **Desenho limpo** (padrão, para
  editar) e **Ver rede completa** (tudo visível: 400 m, todas as linhas, sem oclusão —
  mais pesado).
* **Espaço de coordenadas** (`espaco`): `pixels` é o normal. Se o seu jogo usa a
  projeção no espaço relativo (640x448) e o desenho em pixels da janela, troque para
  `jogo`. **Use o F10 para conferir**: as marcas de canto/centro têm que cair
  exatamente nos cantos/centro da tela.
* **Fade por distância** (`fade_distancia`): nodes/links distantes ficam mais fracos,
  o que reforça a sensação de profundidade.
* **Diagnóstico** (`geral.log_api`): grava a fase do desenho a cada quadro; o F10
  grava também os números da projeção (tela, jogador, câmera, pixels por metro).

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

Se uma área não tem arquivo nenhum, criar um node ali começa a área do zero (nada é
sobrescrito: o `nodesN.dat` só nasce quando você salvar).

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
| Menu não abre | Moon ImGui 1.1.5 instalado? Veja o log em `moonloader/VisualPathEditor.log`. O F7 avisa no chat: `Moon ImGui nao encontrado`, `o painel nao apareceu` (watchdog de 2 s) ou `painel desativado por erro` |
| Textos do painel aparecem como `%s` / `%d` | Bug até a 1.0.6 (o `Text` do Moon ImGui usa só o primeiro argumento). Use a **1.0.7** |
| O painel é pequeno demais | Botões **A-**/**A+** no topo do painel ou *Configurações → Geral → Escala da interface* |
| Cliquei em **Carregar nodes** e nada mudou | O painel estava sem nenhuma área selecionada. Na 1.0.7 o botão seleciona a área do jogador e avisa no chat; sem área selecionada a aba *Editor* lista as áreas carregadas |
| "não carregou a área N" | Não existe `nodesN.dat` no modloader **nem** no `gta3.img`; importe pela aba *Área* |
| Alterações não aparecem no jogo | Saia do jogo e volte (ou desligue o ModLoader e ligue), o jogo só lê os paths no carregamento |
| Salvamento bloqueado | Veja os erros na aba *Salvar*: corrija os marcados ou use "corrigir automaticamente" |
| Arquivo salvo com avisos | O mod pergunta antes; confirme apenas se tiver certeza do que está fazendo |
| Quero voltar atrás | Aba *Salvar* → **reverter** (tira o override do modloader) e **restaurar backup** |
| Nada é desenhado no mundo | O mod só desenha com o jogo jogável (fora da pausa/carregamento). O motivo aparece na aba *Configurações* (`Estado do desenho: …`) e no aviso ao ligar o F8 |
| Jogo lento com o mod ligado | Aba *Configurações* → **Limites de desenho**: reduza `max_nodes` / `max_linhas` ou deixe o *modo leve automático* ligado (ele corta o desenho quando os quadros passam de ~9 ms) |
| Travamento/crash e preciso saber onde | Ligue `Diagnostico no log (log_api)`: o log passa a gravar, a cada quadro, a fase do desenho (`links`, `nodes`, `navis`, `hud`, `minimapa`). A última linha antes do travamento diz em qual fase foi |
| Nodes "colados na tela", não no mapa | Ligue o **F10** (diagnóstico): ele desenha um quadrado vermelho no canto superior esquerdo, uma cruz verde no centro e um quadrado azul no canto inferior direito, além de marcas **no mundo** (amarelo no jogador, magenta 20 m ao norte, ciano 20 m a leste). Me diga onde as marcas caíram e o log mostra os números crus |
| Desenho atravessa paredes | Aba *Configurações* → **Ocultar nodes atrás de paredes/predios (oclusão)** já vem ligado; aumente `oclusao_raio` para checar mais longe ou reduza `oclusao_max_por_quadro` se o FPS cair |
| Muitos quadrados/linhas, tela confusa | Aba *Configurações* → *Render* → botão **Desenho limpo** (padrão). Se ainda quiser menos: reduza `distancia`, `distancia_navis`, `max_nodes` e deixe **Linhas dos links** em *Só do node selecionado* |
| Quero ver a rede inteira (todas as ligações) | Botão **Ver rede completa**, ou mude **Linhas dos links** para *Todas* e aumente `distancia` |
| Crash ao desenhar | O desenho passa por checagens (`exigir_jogo_pronto`, validade das coordenadas, tetos por quadro) e nunca entrega handle/fonte inválidos à API do MoonLoader — veja *Nota de correção* abaixo |

### Nota de correção (crash 0xC0000005)

Até a versão **1.0.0** o HUD podia derrubar o GTA (`MoonLoader.asi`, violação de
acesso lendo o endereço `0x00000004`). Causa: o campo `self.font` era inicializado
como `nil`; em Lua isso **apaga a chave** e a leitura passa a cair na metatable,
devolvendo o *método* `M.font` — ou seja, uma **função Lua** era passada para
`renderFontDrawText`/`renderGetFontDrawTextLength` no lugar da fonte. O jogo lê a
fonte como ponteiro (`ImFont*`), e ler um campo dessa estrutura a partir de um
ponteiro nulo dá exatamente a leitura em `0x4`.

Corrigido em **1.0.2** (campo renomeado para `fontRef`), com três proteções novas:

1. teste de regressão que varre o código e **falha** se qualquer campo do objeto
   tiver o mesmo nome de um método (e o mock agora **recusa** fonte inválida, como
   o jogo faria);
2. nenhuma API nativa recebe handle inválido: `PLAYER_PED or 0` foi eliminado
   (usa `util.playerPed()`, que nunca devolve `0`/negativo/ped inexistente);
3. o desenho só acontece com o jogo jogável, com coordenadas validadas (sem
   `NaN`/infinito), teto de primitivas por quadro, `pcall` em toda chamada nativa e
   modo leve automático.

---

## 10. Histórico de versões

* **1.0.7** — **os textos do painel aparecem de verdade** (o `imgui.Text` do Moon
  ImGui usa **só o primeiro argumento**: o mod mandava o texto como segundo e o
  painel escrevia `%s`/`%d` cru — agora tudo é formatado no Lua e vai como um
  argumento só, com teste que varre as 9 abas atrás de formato cru); **escala da
  interface** (botões **A-/A+** no topo do painel, slider em *Configurações → Geral*
  e `[geral] escala_ui` no INI; padrão **1.35**, aumenta a fonte e a janela);
  **Carregar nodes agora faz o que promete** — carrega a área do jogador,
  **seleciona ela no painel** e avisa no chat (`VPE: area N carregada`), e a aba
  *Editor* passou a listar as áreas já carregadas quando nenhuma está selecionada
  (antes, com o auto-carregar ligado, o clique não mudava nada na tela); linha
  colorida deixou de ser desenhada **duas vezes** (`TextColored`/`TextWrapped` são
  `void` no Moon ImGui — testar o retorno para decidir o fallback duplicava o texto);
  log novo `interface: refs=bool=nativo, int=nativo, ...` (diz se os widgets
  realmente ligaram) e `ImBool/ImInt/ImFloat/...` são detectados **chamando o
  construtor**, nunca por `type() == 'function'`.
* **1.0.6** — **F7 não derruba mais o mod**: o desenho do painel passou a rodar
  dentro de `pcall` (um erro no callback derrubava o script inteiro e, com ele, o
  desenho dos nodes no mundo). Erro no painel agora vai para o log
  (`painel: erro no quadro N`) e para o chat, e depois de 3 erros só o painel é
  desligado, mantendo o desenho. O teclado ganhou avisos no chat (`painel aberto`/
  `painel fechado`, `desenho LIGADO/DESLIGADO`) e a interface um *watchdog* de 2 s
  (`painel: aberto ha 2 s sem nenhum quadro desenhado`).
* **1.0.5** — flags de **navi** passam a ser gravadas de verdade (`WIDTH`,
  `LEFT_LANES`, `RIGHT_LANES`, `LIGHT_DIRECTION`, `TRAFFIC_LIGHT`,
  `TRAIN_CROSSING` em `navi.flags`); a lista de arquivos é reescaneada depois de
  **reverter**/**restaurar backup** (antes o mod continuava achando que o arquivo
  apagado existia); **Reverter** e **Restaurar backup** agora pedem confirmação;
  o checkbox **Criar o link inverso automaticamente** passou a valer de fato
  (desligado = todo link sai de mão única, com aviso no painel); botão
  **Limpar cache do ModLoader** com rótulo próprio; **[TUTORIAL.md](TUTORIAL.md)**.
* **1.0.4** — visual de editor: marcadores de 1,5–6 px, navi em cruz, **só os links
  do node selecionado**, presets **Desenho limpo** / **Ver rede completa**.
* **1.0.3** — oclusão por raycast (nada é desenhado através de prédio) e fade por
  distância.
* **1.0.2** — desenho ancorado no mundo (tamanho em metros, perspectiva) e correção
  do crash do HUD (`fontRef`).
* **1.0.1** — correções de estabilidade do desenho e das fontes.

---

## 11. Língua / Language

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

Good to know:

* The mod only draws while the game is actually playable (not paused/loading). When it
  is holding back, the reason is shown in the settings tab and as a warning when you
  press F8.
* Draw budgets (`max_linhas`, `max_nodes`, `max_navis`) plus an automatic light mode
  keep the frame time in check; set `log_api = true` to log the draw phase of every
  frame (the last line before a freeze tells you where it happened).
* **1.0.7**: panel texts are written for real (Moon ImGui's `imgui.Text` uses **only
  the first argument** — the mod used to pass the text as the second one, so the panel
  showed literal `%s`/`%d`; everything is now formatted in Lua and sent as a single
  argument, with a test that scans all 9 tabs for raw format specifiers).
  **Interface scale** (**A-** / **A+** in the panel, slider in the settings tab,
  `escala_ui` in the INI; default 1.35 — scales font and window). **Load nodes**
  now loads the player's area, **selects it in the panel** and reports it in the chat,
  and the Editor tab lists already-loaded areas when none is selected. Colored lines
  are no longer drawn twice, and the log gained `interface: refs=bool=nativo, ...`.
* **1.0.6**: drawing errors can no longer kill the script (the panel body runs inside
  `pcall`); panel errors are logged (`painel: erro no quadro N`) and chat-reported, and
  after 3 errors only the panel is disabled. Chat notices for F7/F8 and a 2 s watchdog
  (`painel: aberto ha 2 s sem nenhum quadro desenhado`).
* **1.0.5**: navi flag fields (width, left/right lanes, light direction, traffic
  light, train crossing) are actually written to `navi.flags`; the file list is
  rescanned after *Revert* / *Restore backup*; both of those actions ask for
  confirmation; the *create the reverse link automatically* checkbox is honoured
  (with mirroring off every link is one-way, and the panel says so).
* **Clean by default (1.0.4)**: small markers (3-12 px), navi nodes as crosses, and
  **only the selected node's links** are drawn - drawing every link of every node
  turned the city into a web of lines. *Link lines* can be set to *All* and the
  *Show full network* preset brings everything back (400 m range, no occlusion).
* Nodes are drawn with a **world size** (they shrink with distance) and **occlusion**
  (a raycast hides what is behind buildings), so they look anchored in the map instead
  of a flat layer glued to the screen. Press **F10** to draw reference marks
  (screen corners/centre + world marks around the player) and log the raw projection
  numbers if something looks off; if the marks do not land where they should, switch
  `espaco` between `pixels` and `jogo` in the settings tab.
* **1.0.1 fixes a crash** present in 1.0.0: `self.font` was `nil`, so the lookup fell
  through to the metatable and returned the *method* — a Lua function was handed to
  `renderFontDrawText` instead of the font handle, and the game read a null `ImFont*`
  field at address `0x4` (`0xC0000005` in `MoonLoader.asi`). The field is now
  `fontRef`, and regression tests scan the sources for that whole class of bug.

---

## Créditos

* Inspirado em *SA WIP Visual Path Editor 1.0* de **Lightvelox** (modo de edição no jogo).
* Formato dos `nodes*.dat` documentado no GTAMods Wiki / Grand Theft Wiki.
* Feito para MoonLoader (Lua) com Moon ImGui.
