# Tutorial completo — Visual Path Editor 1.0.7

Guia de uso do editor visual de *path nodes* do GTA San Andreas, escrito para quem
nunca mexeu nos arquivos `nodes*.dat`. Explica o que é cada coisa, o que o editor
faz sozinho, o que você precisa decidir, como salvar e como conferir se ficou certo.

> **Pressa?** Faça as seções **1**, **3** e **5**. O resto é referência.

> **Novidades da 1.0.7** (relato de quem testou no jogo): o painel voltou a escrever
> os textos de verdade — antes algumas linhas apareciam como `%s`, porque o
> `imgui.Text` do Moon ImGui usa **só o primeiro argumento** e o mod passava o texto
> como segundo; e agora tem **escala de interface** (botões **A-**/**A+** no topo do
> painel) porque o tamanho padrão do ImGui é pequeno demais. O **Carregar nodes**
> ficou explícito: ele carrega a área onde você está, **seleciona ela no painel** e
> avisa no chat (`VPE: area N carregada`) — antes, com as áreas já carregadas pelo
> auto-carregar, o clique não mudava nada na tela e parecia que o botão estava morto.

## Índice

1. [O que são os path nodes (e o que é cada arquivo)](#1-o-que-são-os-path-nodes-e-o-que-é-cada-arquivo)
2. [Onde o editor grava (e por que seu jogo não corre risco)](#2-onde-o-editor-grava-e-por-que-seu-jogo-não-corre-risco)
3. [Primeiros passos no jogo](#3-primeiros-passos-no-jogo)
4. [Mouse, teclado e o painel](#4-mouse-teclado-e-o-painel)
5. [Criar nodes: veículo, pedestre e barco](#5-criar-nodes-veículo-pedestre-e-barco)
6. [Navi nodes: faixas, semáforos e direção](#6-navi-nodes-faixas-semáforos-e-direção)
7. [Links: ligando a rua](#7-links-ligando-a-rua)
8. [Flags do node: rodovia, estacionamento, spawn](#8-flags-do-node-rodovia-estacionamento-spawn)
9. [Validar antes de salvar](#9-validar-antes-de-salvar)
10. [Salvar e testar no jogo](#10-salvar-e-testar-no-jogo)
11. [Voltar atrás: reverter e restaurar backup](#11-voltar-atrás-reverter-e-restaurar-backup)
12. [Receitas prontas](#12-receitas-prontas)
13. [Referência rápida](#13-referência-rápida)
14. [Problemas comuns](#14-problemas-comuns)
15. [English (short version)](#15-english-short-version)

---

## 1. O que são os path nodes (e o que é cada arquivo)

Os *path nodes* são **pontos invisíveis** que o jogo usa para a IA: por onde os
carros dirigem, por onde os pedestres andam e por onde os barcos navegam. Não são
objetos do mapa — se você apagar, o jogo não trava, mas ninguém mais anda direito
por ali.

O mundo é dividido em **64 áreas** de **750 × 750 unidades**, numa grade **8 × 8**
que começa no canto sudoeste em `(-3000, -3000)`. Cada área é um arquivo
`nodesN.dat` (`nodes0.dat` … `nodes63.dat`). O editor calcula a área pela posição
sozinho: você só anda pelo mapa, e ele carrega o arquivo certo (ou cria uma área
vazia na memória, se o arquivo não existir).

### Os tipos de node

| Tipo | Quem usa | Onde colocar | No desenho |
|---|---|---|---|
| **Node de veículo** | carros, motos, caminhões, polícia, ambulância | ruas, avenidas, estacionamentos, rodovias | quadrado **branco** |
| **Node de pedestre** | pedestres (calçada, travessia, becos) | calçadas e travessias | quadrado **verde** |
| **Node de barco** | barcos e jet-skis | água (mar, lago, rio) | quadrado **azul** |
| **Navi node** | escolhe a faixa/direção do carro | no meio de um link de veículo | cruz **ciano** |
| **Link** | é a "rua" em si: liga dois nodes | entre nodes do mesmo tipo | linha **cinza** (as do node selecionado) |

### O que o formato impõe (o editor respeita e valida)

* **Nodes de veículo vêm primeiro**, depois os de pedestre, dentro do arquivo. O
  editor insere e reindexa sozinho — inclusive os links e as referências de navi.
* **Pedestre só se liga a pedestre**, veículo a veículo, barco a barco. Misturar
  gera aviso na validação.
* **Link de mão dupla** é o normal: o jogo espera A→B **e** B→A. O editor cria os
  dois lados por padrão e avisa quando falta um.
* **Máximo de 15 links por node**, **1024 navi nodes por área**, **65535 nodes por
  área**.
* O campo `LINK_COUNT` (nos flags do node) **é** o número de links dele: o editor
  mantém esse campo certo automaticamente — não edite à mão.
* Coordenadas são guardadas como inteiro em passos de 0,125, com limite
  **±4095,875** (na prática, o editor usa **±4000** como limite de segurança e
  avisa antes).
* **Navi node não tem Z**: ele é um ponto 2D (x, y) na pista.
* Cada **link** guarda o **comprimento** (distância 2D, 0–255). Ao salvar, o editor
  **recalcula** os comprimentos das áreas alteradas — mover um node não estraga
  nada.

---

## 2. Onde o editor grava (e por que seu jogo não corre risco)

O editor **nunca** escreve dentro do `gta3.img` do jogo (a não ser que você ligue a
opção "perigosa" nas configurações, por conta própria). Ele grava em pasta de
ModLoader:

| Pasta | Para que serve |
|---|---|
| `modloader/VisualPath/gta3.img/nodesN.dat` | **é daqui que o jogo carrega** — dentro de uma pasta chamada `gta3.img`, o ModLoader substitui o arquivo do jogo |
| `modloader/VisualPath/export/nodesN.dat` | cópia de conferência/comparação |
| `modloader/VisualPath/backup/nodesN.dat` | **cópia do original**, guardada antes da primeira gravação daquela área |

Se nenhum mod substitui um `nodesN.dat`, o editor lê o original de
`models/gta3.img` e trabalha em cima dele. Nada é alterado até você mandar salvar.

Depois de gravar, o editor **relê o arquivo do disco e compara** com o que deveria
ter saído. Se não bater, ele avisa em vez de dizer que deu certo ("O arquivo gravado
nao confere").

---

## 3. Primeiros passos no jogo

1. Entre no jogo. O mod escreve `VPE: iniciado` no chat e o ícone aparece se houver
   Moon ImGui.
2. Aperte **F7** — o painel abre (título: *Editor Visual de Paths*, com a versão e,
   depois, a área atual). O **F7** também avisa no chat (`painel aberto`/`painel
   fechado`), então dá para saber que o mod respondeu mesmo se a janela demorar a
   aparecer.
3. **Carregar nodes** (aba *Area* ou o botão no topo da aba *Editor*): carrega a área
   onde você está (e, se ligado, as vizinhas), **seleciona ela no painel** e escreve
   no chat `VPE: area N carregada (M nodes) - ela esta selecionada no painel`. Se as
   áreas já estavam carregadas (auto-carregar), o aviso é `ja estava carregada` — e a
   aba *Editor* lista todas as áreas carregadas para você escolher.
4. Aperte **F8** — liga o desenho dos nodes no mundo.
5. **Feche o painel (F7)** e gire a câmera: os marcadores ficam ancorados no mapa
   (tamanho acompanha a distância, e prédios escondem o que está atrás).
6. Abra o painel de novo: o topo mostra a área, a contagem
   (`Nodes: N  Veiculos: N  Pedestres: N  Navi: N  Links: N`) e `(Modificado)` se
   você já mexeu em algo que ainda não foi salvo.

> **Não apareceu nada?** O mod só desenha com o jogo realmente jogável (não na
> pausa/carregamento/replay). Na aba **Configuracoes** existe a linha
> *Estado do desenho: …* que diz o motivo. Problemas de posição dos marcadores:
> aperte **F10** (diagnóstico) — ele desenha marcas de referência e grava os números
> da projeção no log.

---

## 4. Mouse, teclado e o painel

**Regra de ouro:** painel aberto = mouse no painel. Para mexer nos nodes com o
mouse, **feche o painel (F7)**.

### Com o painel fechado (mouse no mundo)

| Ação | Comando |
|---|---|
| Selecionar o node sob o cursor | **botão direito** |
| Arrastar o node selecionado no plano X/Y | **botão esquerdo** (segurar e mover) |
| Realçar um node | só passar o mouse (*hover* vermelho) |

O arrasto é contínuo: ao soltar, o movimento entra no histórico como uma única
operação (Ctrl+Z volta tudo de uma vez).

### Com o painel aberto (numpad move o node)

| Tecla | Efeito |
|---|---|
| NumPad **4 / 6** | −X / +X |
| NumPad **2 / 8** | −Y / +Y (sul / norte) |
| NumPad **3 / 9** | −Z / +Z (baixo / cima) |
| NumPad **5** | cola o node no chão (segurando, repete) |
| **PageUp / PageDown** | ±Z |
| **Ctrl** (com as teclas acima) | passo **fino** = 0,125 |
| **Shift** (com as teclas acima) | passo **grosso** = 8,0 |
| sem modificador | passo **normal** = 1,0 |

Os três passos são configuráveis (*Configuracoes → Edicao*).

### Tamanho do painel (escala) — para ler sem apertar os olhos

O ImGui desenha com fonte de ~13 px e isso é pequeno demais para muita gente. O mod
nasce com **escala 1.35** e há três jeitos de mudar:

| Onde | Como |
|---|---|
| Topo do painel | botões **A-** e **A+** (diminuem/aumentam 0,1 por clique) |
| Aba *Configuracoes → Geral* | slider **Escala da interface** (0,60 a 2,50) |
| INI | `[geral]` `escala_ui = 1.35` |

O mod guarda a escolha no INI na hora. A escala aumenta **a fonte e a janela**
(janela 440×640 × escala) e vale na hora, sem recarregar o jogo. Se a sua build de
ImGui não aceitar `FontGlobalScale` no `ImGuiIO`, o mod cai para o
`SetWindowFontScale` da própria janela — e se nenhum dos dois existir ele avisa no
chat (*"este ImGui nao deixa escalar a fonte"*) e só o tamanho da janela muda.

### Teclas globais (funcionam sempre; todas trocáveis)

| Tecla | Ação (nome no mod) |
|---|---|
| **F7** | Abrir/fechar o menu |
| **F8** | Ligar/desligar a renderização |
| **F9** | Validar a área atual |
| **F5** | Salvar |
| **F6** | Recarregar do disco (descarta o que não foi salvo) |
| **F10** | Diagnóstico do desenho (marcas + log) |
| **Ctrl+Z / Ctrl+Y** | Desfazer / Refazer (até 60 passos) |
| **Insert** | Criar node na mira (do tipo escolhido na aba *Criar/Remover*) |
| **Delete** | Apagar node selecionado (pede confirmação se ele tiver links) |
| **Tab** | Selecionar próximo node (mais perto de você) |
| **G** | Ir até o node selecionado (teleporta) |
| **P** | Colocar o node selecionado **no jogador** |
| **L** | Colocar o node selecionado **na mira** |
| **K** | Colar node no chão |
| **Ctrl+L** | Marcar node como **origem do link** |
| **Enter** | Criar link a partir da origem marcada |

### Seleção, bloqueio e histórico

* **Tab** é o jeito mais rápido de achar um node no meio da rua (ele mostra a
  distância); **G** leva você até ele (ótimo para editar áreas distantes).
* **Bloqueio** (abas *Editor* / *Criar/Remover*): protege um node pronto de ser
  movido/arrastado ou apagado por engano. Nodes bloqueados mostram `[Bloqueio]`.
* A aba **Historico** tem duas listas: **Erros** (mensagens do mod, também escritas
  em `moonloader/VisualPathEditor.log`) e **Alteracoes** (o que cada área
  modificada ganhou/perdeu: `Node: a -> b`, `navi:`, `Link:`, `+novos -removidos`).

---

## 5. Criar nodes: veículo, pedestre e barco

### 5.0 Antes de criar: dois ajustes que evitam retrabalho

Na aba **Criar/Remover**:

1. **Tipo** — a lista marca com `(*)` o que o **Insert** vai criar:
   `Novo node de veiculo`, `Novo node de pedestre`, `Novo node de barco` ou
   `Novo navi node`.
2. **Ligacao** — `Link automatico (node mais proximo)` ou `Link manual`.
   No automático, o node novo já é ligado ao node **do mesmo tipo** mais próximo
   num raio de **40 m**.

Onde o node nasce:

* **Criar na mira** / **Insert**: o ponto onde a câmera cruza o chão (até 12 m);
  se a mira não está no chão, ele cai na sua posição.
* **Criar no jogador**: exatamente onde você está (útil dentro da água, para barco).

Em qualquer caso o node nasce **selecionado**, aparece no painel e, se a área não
tinha arquivo, o editor cria a área vazia na memória (o arquivo só nasce ao salvar).
Posições fora de **±4000** são recusadas.

### 5.1 Node de veículo (carro)

**O que é:** a rua em si. Carros, motos, caminhões, ônibus, polícia e ambulância
andam por esses pontos.

1. Aba *Criar/Remover* → `Novo node de veiculo`.
2. Vá até a rua (de carro ou com **G**/*Ir para o node*). Desça do carro para a mira
   apontar para o chão da pista.
3. Mire no asfalto e aperte **Insert** (ou *Criar na mira*).
4. Ande 10–30 m e repita ao longo da pista. Com o link automático, cada node novo
   já sai ligado ao anterior — é assim que se desenha uma rua.

O que o editor já configurou nesse node:

| Campo | Valor | Por quê |
|---|---|---|
| `Estrada normal` (`NOT_HIGHWAY`) | ligado | o jogo trata como rua comum |
| `Probabilidade de spawn` | 15 (máximo) | o jogo pode gerar veículos aí |
| `Largura do caminho` | 0 (padrão) | — |
| `Flood fill` | 1 | valor típico de fluxo de carros |
| `heuristic` | `0x7FFE` | igual aos arquivos originais |
| posição Z | onde a mira bateu | **K** (ou NumPad 5) cola no chão |

**Conferir depois:** com o node selecionado, veja a lista **Links** na aba *Editor* —
o link para o vizinho e o link de volta devem estar lá (*Você → vizinho* e
*vizinho → você*).

### 5.2 Node de pedestre (ped)

**O que é:** calçada, travessia e caminhos de gente. Carros **ignoram** esses nodes
(eles ficam depois dos veículos dentro do arquivo, e o editor cuida da ordem).

1. Aba *Criar/Remover* → `Novo node de pedestre`.
2. Fique em cima da calçada (ou no meio da travessia) e aperte **Insert**.
3. O link automático procura outro **pedestre** num raio de 40 m — nunca um carro.

Configuração automática:

| Campo | Valor | Por quê |
|---|---|---|
| `Largura do caminho` | **16** | largura da calçada/área de caminhada |
| `Flood fill` | **5** | onde o pedestre "se espalha" |
| `Probabilidade de spawn` | 15 | nascem pedestres aí |
| flags | 0 | sem `Estrada normal` (é calçada, não rua) |

**Como fazer uma calçada:**

* Crie uma linha de ped nodes acompanhando a calçada, 5–15 m entre eles.
* Para a **travessia**, crie um ped node de cada lado da rua e ligue os dois
  (link ped↔ped). É isso que faz o pedestre atravessar no lugar certo.
* Becos e escadarias: mesma coisa, nodes mais próximos (3–8 m).
* Não precisa de navi node em calçada.

### 5.3 Node de barco (boat)

**O que é:** rota de água. Nesse node o jogo usa a flag `BOAT`.

1. Aba *Criar/Remover* → `Novo node de barco`.
2. Vá de barco (ou nade e use *Criar no jogador*).
3. Crie os nodes **dentro da água**, 20–50 m um do outro (barco não precisa da
   precisão de rua).

Configuração automática:

| Campo | Valor |
|---|---|
| `Barco` (`BOAT`) | ligado |
| `Estrada normal` (`NOT_HIGHWAY`) | ligado |
| `Probabilidade de spawn` | 15 |
| `Flood fill` | 2 |

> **Cuidado com o link automático na costa:** ele procura nodes "de veículo" num
> raio de 40 m, e isso inclui carros. Se acontecer, a validação avisa
> (*"barco ligado a node de carro"*). Solução: use `Link manual` para barco, ou
> remova o link errado (*Editor → Links → Remover link*) e ligue no barco certo.

**Como fazer uma rota de barco:**

1. Crie os nodes na água em sequência.
2. `Link manual`: selecione o primeiro → *Marcar como origem* → selecione o próximo →
   **Criar** (ou Ctrl+L e Enter).
3. Repita até o fim da rota. Confira que não há avisos de barco/carro ou barco em
   terra (`F9`).
4. Barcos não usam navi nodes e não precisam de "rua" na costa.

### 5.4 Navi node

Tem seção própria (6) — é o tipo que mais gera dúvida.

### 5.5 Criar node numa área sem arquivo

Se a região não tem `nodesN.dat` (nem no ModLoader, nem no `gta3.img`), o editor
oferece dois caminhos: **criar o node direto** (a área vazia nasce na memória e o
arquivo só é gravado quando você salvar) ou, se preferir explícito, aba *Area* →
**Criar area vazia aqui** (que se recusa a sobrescrever arquivo existente).

---

## 6. Navi nodes: faixas, semáforos e direção

O navi node diz **como** o carro anda no trecho entre dois nodes de veículo: quantas
faixas, largura, semáforo, passagem de trem e a **direção** do fluxo. É o que faz o
carro andar na mão certa em vez de cortar a curva.

Estrutura: o navi é um ponto **2D (x, y)** que aponta para um **node de veículo**
alvo (campo "Associado ao node N"), e o **link** que passa por ele é que guarda a
referência (o *navi link*).

### Três jeitos de criar

**1) Pelo link (o mais correto).** Aba *Editor*, com um node de veículo selecionado,
na lista **Links** cada linha tem o botão **Criar navi** (quando aquele link ainda
não tem um). O navi nasce **no meio do link**, com o alvo sendo o node de **ID
menor** (regra observada nos arquivos originais), largura igual à do node e 1 faixa
de cada lado. O link passa a apontar para ele (nos dois sentidos, se o link for de
mão dupla).

**2) Pela aba Criar/Remover** → `Novo navi node` → **Criar na mira**/**Insert**:
o editor procura o **node de veículo mais próximo até 60 m** (na área atual e depois
nas outras áreas carregadas). Não achou? Ele **recusa** e explica
(*"Nao associado a nenhum node"*) — crie o node de veículo primeiro. A direção
inicial já aponta para o alvo.

**3) Em lote (para arrumar uma área inteira).** Aba **Navi** → botão **Gerar**:
cria um navi para cada link de veículo que ainda não tem um (uma vez por par de
nodes, pulando nodes de barco). Depois você ajusta semáforo/faixas nos que precisam.
O botão **Remover navis inuteis** apaga os navis que **nenhum link** referencia
(sobras de edições).

### Campos do navi

Selecione o navi (aba *Navi* → clique nele, ou *Ir para o node*) e edite na aba
*Editor*, seção **Flags do navi**:

| Campo | Valores | Para que serve |
|---|---|---|
| **Largura** | 0–255 | largura da via nesse ponto (0 = padrão) |
| **Faixas a esquerda** | 0–7 | faixas do sentido esquerdo |
| **Faixas a direita** | 0–7 | faixas do sentido direito |
| **Semaforo** | `Off` / `NS (norte-sul)` / `WE (leste-oeste)` | cruzamento semaforizado nessa direção |
| **Direcao da luz** | ligado/desligado | usa a luz de direção/seta do cruzamento |
| **Trem** | ligado/desligado | passagem de nível (trem cruza ali) |
| **Direcao** | graus, com botões | direção do fluxo; **Angular** aponta para o node alvo |
| **Associado ao node N** | — | qual node ele serve (`Nao associado a nenhum node` = alvo `0xFFFF`: a validação acusa) |

**Regra prática:** em ruas normais, **um navi por link** de veículo já basta.
Semáforo, só em cruzamento semaforizado de verdade (um navi NS e um WE). Em avenida
com pista dupla, ajuste as faixas (ex.: 2 e 2 numa via de quatro faixas) e a largura
para bater com a do node (senão a validação avisa `largura diferente do node alvo`).

---

## 7. Links: ligando a rua

Sem link o node é uma ilha: o carro não sabe que existe caminho ali — e a validação
avisa (*"nao tem nenhum link"*).

### Ligar na mão

1. Selecione o node de **origem**.
2. Aba *Editor* → seção de link → **Marcar como origem** (ou **Ctrl+L**). O painel
   passa a mostrar `Origem do link: Area X / Node Y`.
3. Selecione o node de **destino**. Pode ser de outra área carregada — links entre
   áreas (nas divisas) são normais.
4. Clique **Criar** (ou aperte **Enter**).

O seletor **Link** decide o sentido:

| Opção | O que faz |
|---|---|
| **Bidirecional** (padrão) | cria A→B **e** B→A (o normal em ruas) |
| **Sentido unico** | cria só A→B (só quando a rua é realmente mão única) |

> Nas configurações existe **Criar o link inverso automaticamente**. Se você
> desligar esse espelhamento, **todo** link (manual ou automático) sai de mão única e
> o painel avisa com a linha *"Espelhamento desligado nas configuracoes…"*. Deixe
> ligado, a não ser que esteja fazendo uma via de mão única de verdade.

### Ligar automaticamente

Com `Link automatico (node mais proximo)` na aba *Criar/Remover*, todo node novo já
sai ligado ao mais próximo do mesmo tipo (≤ 40 m) — o jeito prático de desenhar uma
rua nova. O checkbox *Criar navi node automaticamente em links novos* faz o navi do
link nascer junto.

### Conferir e consertar

* Aba *Editor*, lista **Links**: cada linha mostra
  `Link n: area X -> area Y  Distancia d`, com **Ir para o node** e **Remover link**
  (e **Criar navi** quando falta).
* Aviso de *link sem o de volta*: clique **Criar** no sentido que falta (com origem
  marcada), ou deixe o **Corrigir tudo** da validação criar o inverso.
* **Remover link** (o botão grande, embaixo) limpa **todos** os links do node após
  confirmação.

---

## 8. Flags do node: rodovia, estacionamento, spawn

Com um node selecionado, aba *Editor* → **Flags**. A primeira linha mostra os bits
crus (`Bits: 0x…  Links: n`).

### Estrada

| Flag | Quando usar |
|---|---|
| **Rodovia (highway)** | autoestrada/rodovia: via rápida |
| **Estrada normal** | o caso comum (já vem ligado nos nodes que o editor cria) |
| **Barco** | rota de água |
| **Faixa de emergencia** | corredor preferido de polícia/ambulância |
| **Estacionamento** | vaga/estacionamento (carros podem parar) |

`Rodovia` e `Estrada normal` são exclusivas — marcar uma desmarca a outra (`NS
(Rodovia)`/conflito vira aviso de validação se as duas ficarem ligadas).

### Trafego

`Nivel de trafego`: **Cheio** (0) / **Alto** (1) / **Medio** (2) / **Baixo** (3) —
quantos veículos o jogo tenta gerar passando por ali.

### Spawn

`Probabilidade de spawn`: 0–15. **0 = nunca** gera veículo naquele node (aparece o
aviso `Nunca` ao lado). É a causa nº 1 de "minha rua nova ficou vazia".

### Largura e flood

| Campo | Faixa | O que faz |
|---|---|---|
| **Largura do caminho** (`pathWidth`) | 0–255 | quão largo o trecho é (praças, portais, estacionamento) |
| **Flood fill** | 0–255 | valor que a IA usa para propagar a qualidade do caminho (ped 5, carro 1, barco 2) |

### Outros

| Campo | O que faz |
|---|---|
| **Faixa de pedestres** (`ROAD_BLOCK`) | bloqueio/travessia no início de um link |
| **Bits altos** | se o arquivo tinha lixo nos bits não usados, aparece o aviso e o botão **Limpar bits altos** |

---

## 9. Validar antes de salvar

Aperte **F9** (ou use a aba *Salvar*). O relatório tem três níveis:

| Nível | Efeito |
|---|---|
| **Erro** | **bloqueia o salvamento** — o arquivo sairia inválido |
| **Aviso** | o jogo carrega, mas o comportamento pode ficar estranho: o editor **pergunta** antes de salvar |
| **Info** | observação (ex.: área vizinha não carregada, node com um único link) |

### Erros (bloqueiam)

| Código | Em palavras |
|---|---|
| `POS_OUT_OF_RANGE` | coordenada fora do que o formato guarda (4095,875) |
| `LINK_AREA_MISSING` | link apontando para área inexistente (o jogo tem 64: 0–63) |
| `LINK_TARGET_MISSING` | link apontando para node que não existe naquela área |
| `LINK_SELF` | link de um node para ele mesmo |
| `TOO_MANY_LINKS` | mais de 15 links num node |
| `TOO_MANY_NAVIS` | mais de 1024 navi nodes na área |
| `TOO_MANY_NODES` | mais de 65535 nodes na área |
| `VEH_COUNT_INVALID` | contagem de veículos maior que o total de nodes |
| `NAVI_NOT_CONNECTED` | navi sem alvo (`0xFFFF`) |
| `NAVI_TARGET_MISSING` / `NAVI_TARGET_AREA_MISSING` | alvo do navi não existe |
| `NAVI_LINK_AREA_MISSING` / `NAVI_LINK_OUT_OF_RANGE` | link apontando para navi que não existe na área |

### Avisos (o editor pergunta antes de salvar)

`link sem o de volta` · `link duplicado` · `link de pedestre para veiculo` (e o
inverso) · `barco ligado a node de carro` · `node de veiculo em terra com flag de
barco` · `rodovia e estrada normal juntas` · `nao e rodovia nem estrada normal` ·
`probabilidade de spawn zero` · `node sem nenhum link` · `apenas um link (beco sem
saida)` · `nodes na mesma posicao` · `comprimento do link errado` · `altura Z
incomum` · `node flutuando`/`node enterrado` (só até 200 m de você) · `posicao fora
da area` · `navi apontando para pedestre` · `navi sem faixas` · `direcao do navi
zerada`/`ao contrario` · `navi nao associado a nenhum link` · `largura do navi
diferente do node` · `arquivo nodesN.dat nao encontrado`.

### Botões

* **Validar de novo** — roda outra vez.
* **Corrigir tudo** — aplica as correções automáticas que o editor conhece (criar o
  link inverso, remover link duplicado, recalcular comprimentos, ligar o navi ao node
  mais próximo, igualar largura/faixas, colar no chão, limpar bits altos, corrigir
  contagens…) e **revalida**. Repita até não sobrar nada corrigível.
* **Salvar mesmo assim** — grava ignorando os **avisos** (os **erros** continuam
  bloqueando).
* Cada item da lista mostra a área/node/link e um botão **Ir ate** para te levar até
  o problema.

---

## 10. Salvar e testar no jogo

1. **F5** (ou aba *Salvar* → **Salvar alteracoes**).
2. O editor: recalcula os comprimentos → valida → (se houver avisos, pergunta) →
   grava `modloader/VisualPath/gta3.img/nodesN.dat` (e a cópia em `export/`) →
   guarda o **backup** do original na primeira vez → **relê e confere** → limpa o
   cache do ModLoader → avisa no jogo (`VPE: salvo`).
3. A aba *Salvar* mostra o que mudou em cada arquivo
   (`Node: a -> b`, `navi:`, `Link:`, `+novos -removidos`, `Deslocados`) e os
   caminhos gravados.
4. **Saia do jogo e volte.** O GTA lê os paths no carregamento da área — o editor não
   troca a rua com o jogo rodando.
5. Observe: carros na rua nova, pedestres na calçada, barcos na água. Rua "vazia"
   normalmente é `Probabilidade de spawn = 0` ou as pontas sem link com a malha
   existente.

> O `gta3.img` do jogo **não é tocado**. Se algo der errado, veja a seção 11.

---

## 11. Voltar atrás: reverter e restaurar backup

Aba **Area** → abra a área (clique no título dela) e use:

| Botão | O que faz |
|---|---|
| **Reverter (tirar do ModLoader)** | apaga o `nodesN.dat` que o editor gravou na pasta do ModLoader. O jogo volta a usar o arquivo original. |
| **Restaurar backup** | reescreve o arquivo do ModLoader com a cópia guardada **antes da primeira gravação** (estado original) e recarrega a área. |
| **Exportar** | grava só uma cópia em `VisualPath/export/`. |
| **Descartar** | joga fora as alterações **na memória** (não mexe em arquivo). |

Reverter e restaurar **pedem confirmação** (o modal mostra o que vai acontecer).
Depois, saia e volte ao jogo — ou use **Limpar cache do ModLoader** (aba *Salvar*)
para o ModLoader parar de usar o arquivo antigo em cache.

---

## 12. Receitas prontas

### A) Rua nova ligando duas avenidas

1. Vá até uma das pontas. Aba *Criar/Remover*: `Novo node de veiculo` +
   `Link automatico (node mais proximo)`.
2. A cada 10–30 m, **Insert** ao longo do traçado, até a outra avenida.
3. Ligue na malha existente: selecione o node da avenida → *Marcar como origem* →
   selecione o último node novo → **Criar** (os dois sentidos).
4. Aba *Navi* → **Gerar** para criar os navis dos links novos.
5. **F9** → corrija o que aparecer (**Corrigir tudo**) → **F5** → sair e voltar ao
   jogo.

### B) Calçada para pedestre com travessia

1. Aba *Criar/Remover*: `Novo node de pedestre`. Crie a linha na calçada
   (5–15 m entre os nodes), ligados automaticamente.
2. Crie um ped node de cada lado da rua, alinhados com a travessia.
3. Ligue os dois (é a travessia): origem = um lado, destino = o outro, **Criar**.
4. Opcional: um ped node no meio da pista para o pedestre esperar.
5. **F9** / **F5**.

### C) Rota de barco no mar

1. Aba *Criar/Remover*: `Novo node de barco` + `Link manual` (evita ligar em carro).
2. Crie os nodes na água, 20–50 m entre eles.
3. Ligue barco ↔ barco um a um (origem → destino → **Criar**).
4. Confira os avisos (`barco ligado a carro`, `node de veiculo em terra com flag de
   barco`) e corrija.
5. **F9** / **F5**. Barcos só aparecem em água navegável — teste no jogo.

### D) Cruzamento com semáforo

1. Monte o cruzamento com quatro nodes de veículo ligados em cruz (ida e volta).
2. Aba *Navi* → **Gerar**.
3. Selecione o navi do sentido norte-sul → `Semaforo: NS (norte-sul)`; o do
   leste-oeste → `WE (leste-oeste)`.
4. Ajuste `Largura` e `Faixas a esquerda/direita` conforme a pista.
5. **F9** / **F5** e teste: os carros devem alternar.

### E) Estacionamento, rodovia, corredor de emergência

* **Estacionamento:** nodes de veículo nas vagas, flag `Estacionamento`, `Nivel de
  trafego: Baixo`.
* **Rodovia:** flag `Rodovia (highway)` no trecho e `Nivel de trafego: Cheio`.
* **Emergência:** flag `Faixa de emergencia` nos nodes do corredor (polícia e
  ambulância passam a preferir o caminho).

### F) Consertar uma rede quebrada

1. **F9**. Se aparecerem `link sem o de volta`, `comprimento errado`, `navi nao
   associado` etc., clique **Corrigir tudo**.
2. **F9** de novo para ver o que sobrou (o que o editor não decide sozinho aparece
   como aviso/erro).
3. Nos links que sobraram errados: **Remover link** e refaça na mão.
4. **F5**.

### G) Ligar duas áreas (divisa)

1. Carregue as duas áreas (aba *Area* → **Carregar nodes** perto da divisa, ou
   escolha a área na lista `Mundo (0-63)`).
2. Selecione o node de um lado → *Marcar como origem*.
3. Selecione o do outro lado → **Criar**: o link inter-área é criado nos dois
   sentidos.
4. **F9** (link para área não carregada gera só Info).

---

## 13. Referência rápida

### Onde ficam as coisas

* Configuração: `moonloader/config/VisualPathEditor.ini`
* Log: `moonloader/VisualPathEditor.log`
* Arquivos gravados: `modloader/VisualPath/{gta3.img,export,backup}/nodesN.dat`

### Abas do painel

| Aba | Para que serve |
|---|---|
| **Editor** | posição, flags, links e flags do navi do item selecionado; Ir/Desfazer/Refazer/Bloqueio/Apagar |
| **Navi** | lista de navis da área, Ir, Apagar, **Gerar** (em lote), **Remover navis inuteis** |
| **Criar/Remover** | tipo do node novo, Criar na mira/no jogador, modo de ligação, espelhamento, bloqueio, apagar |
| **Area** | carregar/criar/descartar áreas, lista de arquivos e caminhos, Salvar/Exportar/Reverter/Restaurar por área, as 64 áreas do mundo |
| **Salvar** | diferenças por arquivo, validação, Salvar alteracoes, Salvar mesmo assim, Limpar cache do ModLoader |
| **Camera** | HUD minimapa (Tamanho, Distancia, Mundo atual: *Jogo padrao* / *Mapa MTA*, lado), o que desenhar, Altura/Tamanho do node, importar posição do mundo, carregar áreas vizinhas |
| **Configuracoes** | idioma, **escala da interface**, presets de desenho, alcances, cores, oclusão, passos, pastas, teclas |
| **Historico** | log (aba *Erros*) e alterações pendentes (aba *Alteracoes*), Desfazer/Refazer |
| **Ajuda** | versão, caminhos, lista de teclas |

### Presets de desenho (Configuracoes → Renderizacao)

| Botão | O que faz |
|---|---|
| **Desenho limpo** (padrão) | marcadores pequenos (1,5–6 px), só os links do node selecionado, 120 m de alcance, oclusão ligada — para editar |
| **Ver rede completa** | 400 m, todas as linhas da malha, tetos maiores, sem oclusão — para enxergar a topologia (mais pesado) |

### Limites do formato

| Limite | Valor |
|---|---|
| Áreas | 64 (`nodes0.dat` … `nodes63.dat`), 750 × 750 |
| Nodes por área | 65.535 |
| Links por node | 15 |
| Navi nodes por área | 1.024 |
| Coordenada | ±4.095,875 (passo de 0,125) |
| Comprimento do link | 0–255 (recalculado ao salvar) |
| `pathWidth` / `floodFill` | 0–255 |
| `Probabilidade de spawn` | 0–15 (0 = nunca) |
| `Nivel de trafego` | 0–3 (Cheio/Alto/Medio/Baixo) |

### INI (`moonloader/config/VisualPathEditor.ini`)

| Seção / chave | Padrão | Para que serve |
|---|---|---|
| `[geral] idioma` | `pt` | `pt` ou `en` |
| `[geral] carregar_vizinhas` | `true` | carregar as áreas ao redor do jogador |
| `[geral] escala_ui` | `1.35` | tamanho do painel e da fonte (0,60 a 2,50) |
| `[render] links_modo` | `selecionado` | `selecionado`, `todos` ou `nenhum` |
| `[render] distancia` | `120` | alcance do desenho (m) |
| `[render] distancia_navis` | `60` | alcance dos navis (eles são muitos) |
| `[render] oclusao` | `true` | não desenhar o que está atrás de prédio |
| `[render] escala_por_distancia` | `true` | marcador com tamanho de mundo (não "grudado na tela") |
| `[render] espaco` | `pixels` | espaço de coordenadas do desenho; `jogo` se algo parecer deslocado |
| `[edicao] espelhar_links` | `true` | criar o link inverso automaticamente |
| `[edicao] recalcular_comprimentos` | `true` | recalcular comprimentos ao salvar |
| `[edicao] travar_z` | `false` | travar a altura (Z) ao mover |
| `[edicao] passo_fino/normal/grosso` | 0,125 / 1 / 8 | passos do Ctrl / sem modificador / Shift |
| `[salvar] backup` | `true` | guardar cópia do original antes de gravar |
| `[salvar] limpar_cache_modloader` | `true` | avisar para limpar o cache |
| `[salvar] tambem_gta3img_direto` | `false` | **deixe desligado** (escreve no `gta3.img` do jogo) |
| `[map] ativo/tamanho/raio/lado/modo` | `false/320/200/direita/standard` | minimapa da aba *Camera* |
| `[teclas] …` | F7, F8, F9, F5, F6, CTRL_Z, CTRL_Y, INSERT, DELETE, G, P, L, K, TAB, ENTER, CTRL_L, F10 | todas as teclas |

---

## 14. Problemas comuns

| Sintoma | Causa provável / solução |
|---|---|
| "Nao carregou a area N" | Não existe `nodesN.dat` no ModLoader nem no `gta3.img`. Use **Criar area vazia aqui** e salve. |
| Nada aparece desenhado | Só desenha com o jogo jogável (fora de pausa/carregamento). Veja *Estado do desenho* em *Configuracoes*. Se você apertei F8 sem querer, o chat avisa (*desenho DESLIGADO*) e o F8 liga de volta |
| **Apertei F7 e os nodes sumiram e o painel não abriu** | Foi bug da 1.0.5 e anteriores: um erro dentro do desenho do painel derrubava o script (e o desenho junto). Na 1.0.6 o desenho não depende do painel e o mod avisa no chat o motivo; o log (`moonloader/VisualPathEditor.log`) mostra a linha `painel: erro no quadro ...` com o texto exato do erro. Para recuperar na hora (versões antigas): aperte F7 de novo (desliga o estado do painel), F8 duas vezes ou reentre no jogo |
| F7 não faz nada | Aperte F7: o mod avisa no chat. `Moon ImGui nao encontrado` = falta o ImGui 1.1.5 (`moonloader/lib/imgui.lua`); `o painel nao apareceu` = o binding não desenhou nenhum quadro em 2 s (log: `interface: ...`); `painel desativado por erro` = veja as últimas linhas do log |
| O painel é pequeno demais para ler | Use **A+** no topo do painel (ou *Configuracoes → Geral → Escala da interface*). A 1.0.7 nasce com escala 1.35 e aumenta fonte + janela; o INI guarda a escolha |
| A escala mudou a janela mas a fonte continua pequena | A sua build de ImGui não aceita `FontGlobalScale`: o mod avisa no chat (*"este ImGui nao deixa escalar a fonte"*) e passa a escalar só a janela. Atualize o Moon ImGui para 1.1.5 |
| Os textos do painel saem como `%s` / `%d` | Bug até a 1.0.6: o `imgui.Text` do Moon ImGui usa **só o primeiro argumento** e o mod passava o texto como segundo. Instale a **1.0.7** — ela formata no Lua e manda um argumento só (com teste automatizado que varre as 9 abas atrás de `%s`/`%d` cru) |
| Cliquei em **Carregar nodes** e nada aconteceu | Até a 1.0.6 o botão carregava as áreas mas **não selecionava nenhuma**: com o auto-carregar ligado a tela ficava igual e parecia morto. Na 1.0.7 ele seleciona a área do jogador e avisa no chat (`VPE: area N carregada`); se as áreas já estavam carregadas, a aba *Editor* mostra a lista delas para escolher. Se nem assim mudar, veja o chat e o log: o motivo aparece lá |
| Não consigo selecionar com o mouse | Feche o painel (**F7**) — o mouse só trabalha no mundo com o menu fechado. |
| Alterações não aparecem no jogo | O GTA lê os paths no carregamento: saia e volte (ou **Limpar cache do ModLoader**). |
| Salvamento bloqueado | Há **erros**: veja *Historico → Erros* e use **Corrigir tudo**. |
| Apareceu um modal ao salvar | Há **avisos**: leia o resumo e confirme só se tiver certeza. |
| Carros não passam na rua nova | Falta ligar a rua à malha existente (links nas pontas) ou `Probabilidade de spawn` está em 0. |
| Pedestre anda no lugar errado | Falta a travessia (link ped↔ped cruzando a rua) ou existe link ped→veículo para remover. |
| Barco não aparece | Node fora da água (`barco em node de terra`) ou ligado a carro. |
| Navi "não gruda" | Precisa de um node de veículo a ≤ 60 m: crie o navi pelo link (**Criar navi**) ou use **Gerar**. |
| Minha rua nova ligou em lugar estranho | O link automático liga ao mais próximo em 40 m: remova o link errado e crie o certo na mão. |
| Quero voltar tudo | Aba *Area* → **Reverter (tirar do ModLoader)** ou **Restaurar backup**, e recarregue o jogo. |

---

## 15. English (short version)

Visual editor for GTA San Andreas **path nodes** (`nodes*.dat`), 64 areas of
750 × 750 units.

**Quick start:** press **F7** → *Area* tab → **Carregar nodes** (loads the area you
are standing in, selects it in the panel and prints `VPE: area N carregada` in the
chat) → **F8** to draw. If the panel is hard to read, use **A- / A+** at the top of
the panel (or *Configuracoes → Geral → Interface scale*, default **1.35**) — it
scales the font and the window and is saved in the INI. Close the panel (**F7**) and use **right click** to select, **left drag** to
move on X/Y (numpad 4/6/2/8/3/9 nudges, **K** snaps to ground, Ctrl = fine step).
Pick the node type in the *Criar/Remover* tab and press **INSERT** while aiming at
the ground; with auto-link on, the new node connects to the nearest node of the
same kind (≤ 40 m).

**Types:** vehicle (white, roads; `pathWidth` 0, `floodFill` 1), pedestrian (green,
sidewalks; `pathWidth` 16, `floodFill` 5, links only to other peds), boat (blue,
water; needs the BOAT flag and boat↔boat links), navi (cyan cross; 2D point tied to
a vehicle node, carries lanes/traffic light/direction — create it from a link with
**Criar navi**, or in bulk with *Navi → Gerar*).

**Links:** *Editor* tab → **Marcar como origem** (**Ctrl+L**) → select the target →
**Criar** (**Enter**). Bidirectional by default; one-way only when chosen (or when
mirroring is disabled in the settings). At most 15 links per node.

**Flags:** highway / normal road (mutually exclusive), boat, emergency, parking,
traffic level (Cheio…Baixo), spawn probability 0–15 (0 never spawns — the usual
reason a new road stays empty), path width, flood fill, ped crossing.

**Validate & save:** **F9** validates — errors block the save, warnings ask for
confirmation; *Corrigir tudo* auto-fixes what the editor knows how to fix. **F5**
saves into `modloader/VisualPath/gta3.img/` (plus `export/` and `backup/`); the
game's `gta3.img` is never modified. The game reads paths on area load, so leave and
re-enter the game to see the result. *Area tab → Revert / Restore backup* undo
everything (both ask for confirmation).
