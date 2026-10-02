# PythonMT5

Projeto Python integrado ao MetaTrader 5.

## Relatório de Performance (CLI)

Aplicação de linha de comando que conecta ao MetaTrader 5 para acompanhamento em tempo real (atualização a cada 15 segundos) de performance das operações e posições abertas.

### Como Executar

No ambiente Windows (com MetaTrader 5 instalado, aberto e logado na conta):

```bash
python relatorio_performance.py
```

### Funcionalidades

- **Menu interativo**: Seleção de período (`DD/MM/AAAA`), filtro por ativo específico ou "Todos", e início do relatório.
- **Indicadores de operações fechadas**:
  - Resultado total (R$)
  - Lucro bruto (R$)
  - Prejuízo bruto (R$)
  - Quantidade de operações (total, vencedoras, perdedoras)
  - Fator de lucro
- **Posição atual**:
  - Exibição de posições em aberto com Tipo (Compra/Venda), Quantidade, Preço Médio e Lucro/Prejuízo flutuante.
- **Atualização contínua**:
  - Redesenho automático a cada 15 segundos.
  - Pressione `Ctrl+C` a qualquer momento durante o relatório para retornar ao menu principal.

