---
name: grill-product
description: |
  Interrogatório estilo Matt Pocock de um plano de descoberta de produto contra o
  cânone (Adzic/Impact Mapping, Torres/Continuous Discovery Habits, Bland/Testing
  Business Ideas, Amplitude/North Star Playbook, evals-as-PRD), antes de qualquer
  PRD ser escrito. Use quando Douglas trouxer uma ideia de feature, plano de
  descoberta, ou nota bruta de produto ainda não decidida — antes de acionar a
  skill prd-writer. Não use se a nota já contiver outcome numérico, evidência
  linkada e métrica definidos; nesse caso vá direto para prd-writer. Gatilhos:
  "quero fazer uma feature de X", "pensei numa descoberta pra Y", "vale a pena
  priorizar Z", ou qualquer ideia de produto solta que ainda não tem número,
  evidência ou métrica anexados.
---

# Skill: Grill Product — interrogatório de descoberta antes do PRD

## Propósito

Barrar a porta antes do `prd-writer`. O `prd-writer` assume que as decisões de
descoberta já foram tomadas — ele documenta, não decide. Esta skill existe para
o momento anterior: quando a ideia ainda é fuzzy e documentá-la cedo demais
significa formalizar uma suposição como se fosse fato.

> [!IMPORTANT]
> Regra de ouro: nunca invocar a skill prd-writer nem escrever em `docs/raw` a
> partir desta skill enquanto as dez branches abaixo não estiverem resolvidas
> ou explicitamente dispensadas por Douglas.

## Cinco regras

Uma pergunta por turno · sempre dar uma resposta recomendada · explorar
`docs/raw` antes de perguntar, para não repetir o que já está documentado ·
andar a árvore em profundidade, não em largura · rastrear o que já foi
respondido e as dependências entre respostas.

## Árvore de decisão

**Branch 1 — O que:** O que exatamente essa mudança faz, numa frase que
alguém fora do time entenderia sem jargão? Recomendado: reduzir a uma frase,
sem termo técnico interno. Cânone: Adzic, *Impact Mapping* (nível "What").

**Branch 2 — Porque:** Que problema fica sem resposta se isso não for feito
agora? Recomendado: amarrar à Evidência (branch 3) — motivo sem prova é
justificativa solta. Cânone: Torres, *Continuous Discovery Habits*; Adzic,
*Impact Mapping* (nível "Why").

**Branch 3 — Evidência:** Que sinal — log, registro, dado de uso — sustenta
que isso resolve o problema certo? Quantas ocorrências independentes, não só
uma vez? Recomendado: 3+ ocorrências com data/contexto; uma ocorrência isolada
é anedota, não evidência. Cânone: Torres; Bland, *Testing Business Ideas*.

**Branch 4 — Objetivo:** Qual outcome mensurável, com um número, essa mudança
persegue? Recomendado: exigir o número — sem ele é intenção, não outcome.
Cânone: Torres, *Continuous Discovery Habits*.

**Branch 5 — Como:** Em termos gerais de abordagem — não de tela ou banco —
como isso resolve o problema? Recomendado: descrever o mecanismo, não a
implementação; implementação é trabalho do prd-writer depois. Cânone: Adzic,
*Impact Mapping* (nível "How").

**Branch 6 — Persona:** Quem é o usuário-alvo, especificamente — não
"usuário" genérico? Recomendado: nome ou perfil concreto, ligado a uma
persona existente em `docs/prd/personas.md` se houver. Cânone: Adzic,
*Impact Mapping* (nível "Who").

**Branch 7 — Métrica:** A métrica de sucesso é uma métrica de entrada
(leading) com árvore de contribuintes, ou é receita/vaidade? Recomendado:
métrica de entrada; funil exige banda de benchmark, não número solto. Cânone:
Amplitude, *The North Star Playbook*.

**Branch 8 — Eval spec:** Se alguma parte é probabilística (LLM, scoring,
geração), onde está o eval — golden set, rubrica, SLO de guardrail?
Recomendado: escrever a spec do eval antes de codar. Esta branch só ativa se
houver componente de IA no plano — senão, pule. Cânone: evals-as-PRD.

**Branch 9 — Fora de escopo:** O que alguém poderia assumir que está
incluído, mas explicitamente não está? Recomendado: listar exclusões mesmo
óbvias — óbvio pra quem interrogou não é óbvio pra quem lê o PRD depois.
Cânone: Adzic, *Impact Mapping* (uso de corte de escopo — mapear só os
impactos que servem ao objetivo e cortar o resto).

**Branch 10 — Dependências:** Que time, sistema ou outro PRD precisa estar
pronto antes disso rodar? Recomendado: se não houver nenhuma, registrar
"nenhuma" explicitamente — silêncio não é o mesmo que zero dependências.
Cânone: — (em aberto; nenhuma fonte validada ainda para este item
especificamente).

**Campos fora do molde de branch (sem pergunta forçada):**

- **Imagens/Anexo** — slot de artefato. Se Douglas colar ou referenciar uma
  imagem durante o interrogatório, anexar; não gera turno de pergunta.
- **Pendências de descoberta** — não é interrogada por si só. É o resumo,
  montado ao final, de quais das dez branches acima não foram resolvidas
  antes de a nota ser salva.

> [!NOTE]
> Decisão em aberto, não resolvida com Douglas ainda: "Itens & Persona" foi
> mencionado como possível campo distinto da Persona (branch 6), mas a
> distinção nunca foi definida. Não virou branch. Se isso for retomado,
> revisar esta árvore antes de considerar o design fechado.

## Formato de saída por turno

```
Q[i]/[total]: [pergunta precisa]
Recomendado: [resposta + justificativa citando o cânone]
(Confirma, ou sobrepõe?)
```

## Condições de parada

- **Todas as dez branches resolvidas** (ou dispensadas explicitamente por
  Douglas) — grave em `docs/raw/yyyymmdd-<slug>.md` — data do dia, slug em
  kebab-case derivado do Objetivo — um arquivo com este formato exato:

```markdown
## Pedido Original
[texto literal do pedido/ideia que Douglas trouxe ao abrir o interrogatório —
o $ARGUMENTS original ou a mensagem colada, sem edição, resumo ou paráfrase]

## Contexto de Descoberta
- **O que:** [resposta da branch 1]
- **Porque:** [resposta da branch 2]
- **Evidência:** [resposta da branch 3]
- **Objetivo:** [resposta da branch 4]
- **Como:** [resposta da branch 5]
- **Persona:** [resposta da branch 6]
- **Métrica:** [resposta da branch 7]
- **Eval spec:** [resposta da branch 8 — omitir esta linha inteira se a
  branch não ativou, ou seja, se não há componente de IA no plano]
- **Fora de escopo:** [resposta da branch 9]
- **Dependências:** [resposta da branch 10]
```

  Se houver imagem/anexo relevante, referenciar logo abaixo do bloco.
  Pergunte se deve seguir para o `prd-writer` com essas decisões já
  travadas. Só grave e só invoque `prd-writer` com confirmação explícita.
  Depois de gravar, registre no ledger (ver seção **Registro em
  `docs/raw/raws.md`** abaixo).

- **Douglas diz "para de interrogar, roda assim mesmo"** — grave o mesmo
  bloco `## Pedido Original` + `## Contexto de Descoberta`, preenchendo com
  o que já foi respondido, e adicione logo abaixo:

```markdown
## Pendências de Descoberta
- Branch [n] — [nome da branch]: não resolvida.
```

  listando cada branch que ficou sem resposta. Essa segunda seção só existe
  quando há pendência. Aí sim pode seguir para `prd-writer`, mas com esse
  aviso explícito no topo da nota que ele vai processar. Depois de gravar,
  registre no ledger do mesmo jeito — pendência não isenta do registro.

- **Abandonado no meio** — não invoque `prd-writer`. Ofereça salvar o
  interrogatório parcial como referência para retomar depois. Não registre
  no ledger — o ledger é só para arquivos que efetivamente entram em
  `docs/raw`.

## Registro em `docs/raw/raws.md`

Toda vez que esta skill cria um arquivo novo em `docs/raw`, adicione uma
linha à tabela em `docs/raw/raws.md`. Se o arquivo não existir ainda, crie
com o cabeçalho abaixo antes de adicionar a primeira linha:

```markdown
# Índice de Notas Brutas (docs/raw)

| Data/Hora | Arquivo | PRD |
| :--- | :--- | :--- |
```

Nova linha, sempre com a coluna PRD vazia — quem preenche essa coluna é o
`prd-writer`, não esta skill:

```markdown
| DD/MM/AAAA HH:MM | <nome-do-arquivo.md> | |
```

Data/Hora é o momento exato da gravação, não a data do slug do nome do
arquivo (que é só a data do dia, sem hora). Nunca preencha a coluna PRD por
conta própria — isso é sinal de que a nota já foi tratada, e quem sabe
disso é o `prd-writer`.

## Distinto de

- **prd-writer**: documenta uma decisão já tomada em PRD ARO+BDD. Esta skill
  decide se a decisão está pronta para ser documentada.
- Revisão de escrita/estilo: isso aqui não julga clareza de texto, julga se
  o que/porque/evidência/objetivo/como/persona/métrica/eval/escopo/
  dependências estão de pé.
