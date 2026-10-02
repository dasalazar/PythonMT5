## Pedido Original
Hoje o MT5 tem uma exibição de relatório de performance bem difícil compreensão.
Portanto eu quero criar uma aplicação Python CLI aqui nesse projeto que faça essa conexão com o MT5, e extraia os dados das posições.

- Deve haver filtro por data ini e fim, somente data, não considerar horário. Escolher um range de data considera-se que é do início do dia da data ini até o fim da data fim
- Deve ser possível acompanhar todos os ativos, ou algum em específico
- A verificação deve ocorrer a cada 15 seg para atualização do número. Ou seja, se eu abrir o relatório de performance, ele deve ser consultado a cada 15 seg para atualização de posição
- Formato de exibição deve ser:
    - Resultado total
    - Lucro bruto
    - Prejuízo bruto
    - Quantidade de operações
    - Quantidade de operações vencedoras
    - Quantidade de operações perdedoras
    - Fator de lucro
    - Posição atual
        - Tipo: Compra ou venda
        - Quantidade
        - Preço médio
        - Lucro/Prejuízo

Deve ser utilizado a biblioteca python do mt5
Deve ser criado um menu na aplicação CLI

## Contexto de Descoberta
- **O que:** Um programa de terminal que lê do MetaTrader 5 as operações do dia (ou do período escolhido) e mostra, de forma clara e atualizada a cada 15 segundos, quanto Douglas ganhou ou perdeu e qual posição está aberta.
- **Porque:** Hoje não existe uma visão rápida e legível do resultado e da posição atual durante o pregão. O relatório nativo do MT5 é difícil de entender e não atualiza sozinho, então é preciso interpretá-lo manualmente enquanto se opera.
- **Evidência:** Problema recorrente relatado por Douglas (relatório nativo do MT5 difícil de entender), sem ocorrências datadas. Evidência fraca: não há 3+ ocorrências com data/contexto.
- **Objetivo:** Saber o resultado do dia e a posição atual em até 15 segundos, sem abrir nem interpretar o relatório do MT5, com os números batendo 100% com o histórico do MT5.
- **Como:** Aplicação Python de linha de comando, rodando no Windows junto ao terminal MT5. Conecta ao MT5 pela biblioteca oficial, lê o histórico de negociações do período escolhido e as posições abertas, calcula os indicadores e redesenha o relatório a cada 15 segundos. Um menu permite escolher o período (data inicial e final, sem horário) e o ativo (todos ou um específico).
- **Persona:** Douglas, trader pessoa física de WINFUT (mini-índice, B3), que opera com EAs e manualmente no MT5 e acompanha o resultado do dia durante o pregão. Não existe `docs/prd/personas.md`; a persona deve ser criada pelo prd-writer.
- **Métrica:** (1) Divergência entre o resultado exibido e o histórico oficial do MT5 no mesmo período: meta R$ 0,00 em todos os dias conferidos. (2) Defasagem entre uma mudança de posição no MT5 e a atualização na tela: no máximo 15 s.
- **Fora de escopo:** Enviar, modificar ou fechar ordens (somente leitura); interface gráfica ou web; gráficos, curva de capital e exportação (CSV/PDF); suporte a Profit (Nelogica); execução no macOS; histórico em banco de dados ou persistência entre execuções; múltiplas contas ou corretoras simultâneas; filtro por horário.
- **Dependências:** Terminal MetaTrader 5 instalado, aberto e logado na conta, no Windows; Python e pacote `MetaTrader5` (só Windows) instalados nessa máquina; conta com histórico de negociações acessível pelo MT5. Nenhum outro PRD nem time externo. Validação só ocorre no Windows (CLAUDE.md).
