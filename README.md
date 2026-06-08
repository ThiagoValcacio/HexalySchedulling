# TCC Hexaly

Projeto de otimização para alocação de tarefas a mecânicos usando o solver Hexaly.
A solução combina um modelo LSP em `model.lsp` com um arquivo de configuração em `cfw.lsp` e instâncias de teste em `Instancias/`.

## Visão geral

- `model.lsp`: modelo principal do problema, executado pelo Hexaly.
- `cfw.lsp`: carrega a instância de entrada e define conjuntos, parâmetros e regras de leitura.
- `run_tests.ps1`: script PowerShell que executa `hexaly.exe` para todas as instâncias em `Instancias/` e grava resultados em `resultados_testes/`.
- `Instancias/`: instâncias de problemas em formato de texto.
- `Outputs/`: resultados e logs de execuções anteriores organizados por instância.
- `resultados_testes/`: saída consolidada das execuções de teste e resumo CSV.
- `Auxiliares/`: scripts auxiliares para geração de instâncias e processamento de resultados.
- `gurobi_gap.py`: implementação alternativa usando Gurobi para o problema GAP (apenas referência/uso Python).

## Requisitos

- Hexaly Optimizer instalado e acessível via `hexaly.exe` no PATH ou na pasta do projeto.
- Windows PowerShell para executar `run_tests.ps1`.
- Python 3 se for usar os scripts auxiliares em `Auxiliares/` ou `gurobi_gap.py`.

## Como executar

### Executar o modelo para uma instância específica

1. Edite `cfw.lsp` e altere `instanceFile` para a instância desejada, por exemplo:
   - `instancias/Real_bh.txt`
   - `instancias/10_30.txt`
2. Execute o Hexaly no diretório do projeto:

```powershell
hexaly.exe .\model.lsp
```

### Executar todos os testes em lote

No PowerShell, execute:

```powershell
.
un_tests.ps1
```

O script:
- lê `cfw.lsp` para determinar o padrão das instâncias;
- executa `hexaly.exe .\model.lsp` para cada arquivo `*.txt` em `Instancias/`;
- grava resultados em `resultados_testes/`;
- cria `resumo_resultados.csv` com métricas de desempenho.

## Diretório de saída

- `Outputs/`: resultados consolidados em subpastas por instância.
- `resultados_testes/`: logs de saída e resumo dos testes.
- `Auxiliares/`: scripts para geração e análise de instâncias.

## Observações

- O projeto está escrito em LSP para o ambiente Hexaly.
- O módulo `cfw.lsp` faz a leitura do formato específico de instância definido em `Instancias/`.
- Caso queira adicionar novas instâncias, salve o arquivo em `Instancias/` e ajuste `cfw.lsp` ou `run_tests.ps1` se necessário.

## Contato

Este repositório faz parte de um trabalho de TCC, com foco em otimização de escalação e alocação de mecânicos.
