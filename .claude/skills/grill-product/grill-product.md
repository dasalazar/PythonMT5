---
description: Interrogatório estilo Matt Pocock de um plano de descoberta de produto contra o cânone (Adzic/Impact Mapping, Torres/Continuous Discovery Habits, Bland/Testing Business Ideas, Amplitude/North Star Playbook, evals-as-PRD) antes de liberar o prd-writer. Uma pergunta por turno, com resposta recomendada; recusa acionar o prd-writer até as dez decisões (O que, Porque, Evidência, Objetivo, Como, Persona, Métrica, Eval spec, Fora de escopo, Dependências) estarem travadas ou dispensadas. Use antes de mandar uma nota bruta para docs/raw.
argument-hint: <ideia, nota bruta, ou plano de descoberta a interrogar>
---

# /grill-product — interroga um plano de descoberta antes de virar PRD

Interrogue o plano abaixo. Não escreva nada em `docs/raw` nem acione o prd-writer ainda:

$ARGUMENTS

Cinco regras (preservadas de Matt Pocock, MIT): uma pergunta por turno · sempre dar uma resposta recomendada · explorar `docs/raw` antes de perguntar (não repita o que já está documentado) · andar a árvore de decisão em profundidade, não em largura · rastrear o que já foi respondido e as dependências entre respostas.

## Árvore de decisão

**Branch 1 — O que:** "O que exatamente essa mudança faz, numa frase que alguém fora do time entenderia sem jargão? Recomendado: reduzir a uma frase, sem termo técnico interno. Cânone: Adzic, Impact Mapping (nível 'What')."

**Branch 2 — Porque:** "Que problema fica sem resposta se isso não for feito agora? Recomendado: amarrar à Evidência (branch 3) — motivo sem prova é justificativa solta. Cânone: Torres, Continuous Discovery Habits; Adzic, Impact Mapping (nível 'Why')."

**Branch 3 — Evidência:** "Que sinal — log, registro, dado de uso — sustenta que isso resolve o problema certo? Quantas ocorrências independentes, não só uma vez? Recomendado: 3+ ocorrências com data/contexto; uma ocorrência isolada é anedota, não evidência. Cânone: Torres; Bland, Testing Business Ideas."

**Branch 4 — Objetivo:** "Qual outcome mensurável, com um número, essa mudança persegue? Recomendado: exigir o número — sem ele é intenção, não outcome. Cânone: Torres, Continuous Discovery Habits."

**Branch 5 — Como:** "Em termos gerais de abordagem — não de tela ou banco — como isso resolve o problema? Recomendado: descrever o mecanismo, não a implementação; implementação é trabalho do prd-writer depois. Cânone: Adzic, Impact Mapping (nível 'How')."

**Branch 6 — Persona:** "Quem é o usuário-alvo, especificamente — não 'usuário' genérico? Recomendado: nome ou perfil concreto, ligado a uma persona existente em docs/prd/personas.md se houver. Cânone: Adzic, Impact Mapping (nível 'Who')."

**Branch 7 — Métrica:** "A métrica de sucesso aqui é uma métrica de valor de entrada (leading) com árvore de contribuintes, ou é receita/vaidade? Recomendado: métrica de entrada; se for métrica de funil, exija banda de benchmark, não número solto. Cânone: Amplitude, The North Star Playbook."

**Branch 8 — Eval spec:** "Se alguma parte do plano é probabilística (LLM, scoring, geração), onde está o eval — golden set, rubrica, SLO de guardrail? Recomendado: escrever a especificação do eval antes de qualquer linha de código; sem isso, o que sai é vibe-check, não produto testado. Esta branch só ativa se houver componente de IA no plano — senão, pule. Cânone: evals-as-PRD."

**Branch 9 — Fora de escopo:** "O que alguém poderia assumir que está incluído, mas explicitamente não está? Recomendado: listar exclusões mesmo óbvias — óbvio pra quem interrogou não é óbvio pra quem lê o PRD depois. Cânone: Adzic, Impact Mapping (uso de corte de escopo — mapear só os impactos que servem ao objetivo e cortar o resto)."

**Branch 10 — Dependências:** "Que time, sistema ou outro PRD precisa estar pronto antes disso rodar? Recomendado: se não houver nenhuma, registrar 'nenhuma' explicitamente — silêncio não é o mesmo que zero dependências. Cânone: — (em aberto; nenhuma fonte validada ainda para este item especificamente)."

**Campos fora do molde de branch (sem pergunta forçada):**

- **Imagens/Anexo** — slot de artefato. Se o usuário colar ou referenciar uma imagem durante o interrogatório, anexar; não gera turno de pergunta.
- **Pendências de descoberta** — não é interrogada por si só. É o resumo, montado ao final, de quais das dez branches acima não foram resolvidas antes de a nota ser salva.

> [!NOTE]
> Decisão em aberto, não resolvida com Douglas ainda: "Itens & Persona" foi mencionado como possível campo distinto da Persona (branch 6), mas a distinção nunca foi definida. Não virou branch. Se isso for retomado, revisar esta árvore antes de considerar o design fechado.

## Formato de saída por turno

```
Q[i]/[total]: [pergunta precisa]
Recomendado: [resposta + justificativa citando o cânone]
(Confirma, ou sobrepõe?)
```

## Condições de parada

- **Todas as dez branches resolvidas** (ou dispensadas explicitamente por Douglas) → grava em `docs/raw/yyyymmdd-<slug>.md` — data do dia, slug em kebab-case derivado do Objetivo — um arquivo com este formato exato:

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
- **Eval spec:** [resposta da branch 8 — omitir esta linha inteira se a branch não ativou, ou seja, se não há componente de IA no plano]
- **Fora de escopo:** [resposta da branch 9]
- **Dependências:** [resposta da branch 10]
```

Se houver imagem/anexo relevante, referenciar logo abaixo do bloco. Só grava com confirmação explícita de Douglas. Depois de gravar, registrar no ledger (ver seção **Registro em `docs/raw/raws.md`** abaixo).

- **Douglas diz "para de interrogar, roda assim mesmo"** → grava o mesmo bloco `## Pedido Original` + `## Contexto de Descoberta`, preenchendo com o que já foi respondido, e adiciona logo abaixo:

```markdown
## Pendências de Descoberta
- Branch [n] — [nome da branch]: não resolvida.
```

listando cada branch que ficou sem resposta. Essa segunda seção só existe quando há pendência — nota com todas as branches resolvidas não a inclui. Depois de gravar, registrar no ledger do mesmo jeito — pendência não isenta do registro.

- **Abandonado no meio** → salva o grill parcial em `product-grill-{timestamp}.md`, fora de `docs/raw`, para não contaminar a fila do prd-writer com algo incompleto. Não registra no ledger — o ledger é só para arquivos que efetivamente entram em `docs/raw`.

## Registro em `docs/raw/raws.md`

Toda vez que este comando cria um arquivo novo em `docs/raw`, adicionar uma linha à tabela em `docs/raw/raws.md`. Se o arquivo não existir ainda, criar com o cabeçalho abaixo antes de adicionar a primeira linha:

```markdown
# Índice de Notas Brutas (docs/raw)

| Data/Hora | Arquivo | PRD |
| :--- | :--- | :--- |
```

Nova linha, sempre com a coluna PRD vazia — quem preenche essa coluna é o `prd-writer`, não este comando:

```markdown
| DD/MM/AAAA HH:MM | <nome-do-arquivo.md> | |
```

Data/Hora é o momento exato da gravação, não a data do slug do nome do arquivo (que é só a data do dia, sem hora). Nunca preencher a coluna PRD por conta própria — isso é sinal de que a nota já foi tratada, e quem sabe disso é o `prd-writer`.

## Distinto de

- **prd-writer** — transforma nota já decidida em PRD ARO+BDD. Este comando roda antes, sobre a nota ainda fuzzy, e não escreve PRD nenhum.
- Interrogatório genérico de plano (sem cânone de produto) — isso aqui grilha especificamente contra o que/porque/evidência/objetivo/como/persona/métrica/eval/escopo/dependências, não contra qualidade de escrita ou viabilidade técnica.
