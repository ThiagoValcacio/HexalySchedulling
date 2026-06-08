import pandas as pd
import matplotlib.pyplot as plt
from io import StringIO
from pathlib import Path

ARQUIVO_LOG = "saida.txt"
PASTA_SAIDA = Path("gantt_outputs")
PASTA_SAIDA.mkdir(exist_ok=True)

def carregar_gantt(arquivo_log: str) -> pd.DataFrame:
    from pathlib import Path
    from io import StringIO
    import pandas as pd

    caminho = Path(arquivo_log).resolve()

    print(f"Lendo arquivo: {caminho}")

    if not caminho.exists():
        raise FileNotFoundError(f"Arquivo não encontrado: {caminho}")

    encodings = ["utf-8-sig", "utf-16", "latin1"]

    conteudo = None
    encoding_usado = None

    for enc in encodings:
        try:
            with open(caminho, "r", encoding=enc) as f:
                conteudo = f.read()
            encoding_usado = enc
            break
        except UnicodeError:
            pass

    if conteudo is None:
        raise ValueError("Não foi possível ler o arquivo com os encodings testados.")

    print(f"Encoding usado: {encoding_usado}")

    linhas = []
    for linha in conteudo.splitlines():
        linha_limpa = linha.strip()

        # mais robusto que startswith puro
        if "GANTT;" in linha_limpa:
            idx = linha_limpa.find("GANTT;")
            linhas.append(linha_limpa[idx:])

    print(f"Linhas GANTT encontradas: {len(linhas)}")

    if not linhas:
        print("\nPrimeiras 20 linhas lidas pelo Python:")
        for linha in conteudo.splitlines()[:20]:
            print(repr(linha))

        raise ValueError("Nenhuma linha GANTT encontrada no arquivo.")

    texto = "\n".join(linhas)

    df = pd.read_csv(StringIO(texto), sep=";")

    # Remove cabeçalhos repetidos
    df = df[df["tipo"] != "tipo"].copy()

    df["inicio_idx"] = df["inicio_idx"].astype(int)
    df["fim_idx"] = df["fim_idx"].astype(int)
    df["duracao"] = df["fim_idx"] - df["inicio_idx"] + 1

    return df

def ordenar_mecanicos(mecanicos):
    return list(mecanicos)

def carregar_conflitos_txt(arquivo_log: str) -> pd.DataFrame:
    caminho = Path(arquivo_log).resolve()

    if not caminho.exists():
        raise FileNotFoundError(f"Arquivo não encontrado: {caminho}")

    encodings = ["utf-8-sig", "utf-16", "latin1"]

    conteudo = None
    encoding_usado = None

    for enc in encodings:
        try:
            with open(caminho, "r", encoding=enc) as f:
                conteudo = f.read()
            encoding_usado = enc
            break
        except UnicodeError:
            pass

    if conteudo is None:
        raise ValueError("Não foi possível ler o arquivo com os encodings testados.")

    linhas = []
    for linha in conteudo.splitlines():
        linha_limpa = linha.strip()

        if "CONFLITO_TXT;" in linha_limpa:
            idx = linha_limpa.find("CONFLITO_TXT;")
            linhas.append(linha_limpa[idx:])

    if not linhas:
        return pd.DataFrame(
            columns=[
                "mecanico_original",
                "job",
                "chegada_idx",
                "chegada",
                "tempo_previsto_slots",
                "tempo_previsto_min",
                "especialidade",
            ]
        )

    texto = "\n".join(linhas)

    df = pd.read_csv(StringIO(texto), sep=";")

    # Remove cabeçalhos repetidos, caso existam
    df = df[df["mecanico_original"] != "mecanico_original"].copy()

    df["chegada_idx"] = df["chegada_idx"].astype(int)
    df["tempo_previsto_slots"] = df["tempo_previsto_slots"].astype(int)
    df["tempo_previsto_min"] = df["tempo_previsto_min"].astype(int)

    return df

def gerar_txt_conflitos(df_conflitos: pd.DataFrame, arquivo_saida: str):
    caminho_saida = PASTA_SAIDA / arquivo_saida

    if df_conflitos.empty:
        texto = "Nenhum job conflitante encontrado."
        caminho_saida.write_text(texto, encoding="utf-8")
        print(f"TXT de conflitos salvo em: {caminho_saida}")
        return

    df_saida = df_conflitos.copy()

    df_saida = df_saida.sort_values(
        by=["mecanico_original", "chegada_idx", "job"]
    )

    linhas = []
    linhas.append("JOBS CONFLITANTES DO SCHEDULING")
    linhas.append("=" * 40)
    linhas.append("")

    for _, row in df_saida.iterrows():
        linhas.append(f"Job: {row['job']}")
        linhas.append(f"Mecânico original: {row['mecanico_original']}")
        linhas.append(f"Chegada: {row['chegada']} (slot {row['chegada_idx']})")
        linhas.append(
            f"Tempo previsto: {row['tempo_previsto_slots']} slots "
            f"({row['tempo_previsto_min']} minutos)"
        )
        linhas.append(f"Especialidade: {row['especialidade']}")
        linhas.append("-" * 40)

    texto = "\n".join(linhas)

    caminho_saida.write_text(texto, encoding="utf-8")

    print(f"TXT de conflitos salvo em: {caminho_saida}")

def plot_gantt(
    df: pd.DataFrame,
    tipo: str,
    titulo: str,
    arquivo_saida: str,
    include_lunch: bool = False
):
    dados = df[df["tipo"] == tipo].copy()

    if dados.empty:
        print(f"Nenhum dado encontrado para {tipo}.")
        return

    dados["is_almoco"] = (
        dados["job"].astype(str).str.lower().isin(["almoco", "almoço"])
        | dados["status"].astype(str).str.lower().isin(["almoco", "almoço"])
        | dados["tipo"].astype(str).str.upper().eq("ALMOCO")
    )

    # Mantém o comportamento antigo por padrão:
    # o Gantt FINAL normal não mostra almoço.
    if not include_lunch:
        dados = dados[~dados["is_almoco"]].copy()

    # Quando for o Gantt com almoço, também captura linhas GANTT;ALMOCO;...
    if include_lunch:
        dados_almoco = df[df["tipo"].astype(str).str.upper() == "ALMOCO"].copy()

        if not dados_almoco.empty:
            dados_almoco["is_almoco"] = True
            dados = pd.concat([dados, dados_almoco], ignore_index=True)

        dados = dados.drop_duplicates(
            subset=["mecanico", "job", "inicio_idx", "fim_idx", "status"]
        ).copy()

    if dados.empty:
        print(f"Nenhum dado encontrado para {tipo} após filtros.")
        return

    mecanicos = ordenar_mecanicos(dados["mecanico"].unique())
    y_map = {m: i for i, m in enumerate(mecanicos)}

    fig, ax = plt.subplots(figsize=(16, 7))

    for _, row in dados.iterrows():
        y = y_map[row["mecanico"]]

        is_almoco = bool(row["is_almoco"])

        if is_almoco:
            ax.barh(
                y=y,
                width=row["duracao"],
                left=row["inicio_idx"],
                height=0.28,
                edgecolor="black",
                color="#d9d9d9",
                hatch="///",
                linewidth=0.8,
                zorder=4
            )

            ax.text(
                row["inicio_idx"] + row["duracao"] / 2,
                y,
                "Almoço",
                ha="center",
                va="center",
                fontsize=7,
                zorder=5
            )

        else:
            ax.barh(
                y=y,
                width=row["duracao"],
                left=row["inicio_idx"],
                height=0.55,
                edgecolor="black",
                zorder=2
            )

            ax.text(
                row["inicio_idx"] + row["duracao"] / 2,
                y,
                row["job"],
                ha="center",
                va="center",
                fontsize=8,
                zorder=3
            )

    ax.set_yticks(list(y_map.values()))
    ax.set_yticklabels(list(y_map.keys()))
    ax.set_title(titulo)
    ax.set_xlabel("Slots de 10 minutos")

    ticks = list(range(0, int(df["fim_idx"].max()) + 1, 3))

    mapa_horas = (
        df[["inicio_idx", "inicio"]]
        .drop_duplicates()
        .set_index("inicio_idx")["inicio"]
        .to_dict()
    )

    labels = [mapa_horas.get(t, "") for t in ticks]

    ax.set_xticks(ticks)
    ax.set_xticklabels(labels, rotation=45)

    ax.grid(axis="x", linestyle="--", alpha=0.4)

    plt.tight_layout()
    caminho = PASTA_SAIDA / arquivo_saida
    plt.savefig(caminho, dpi=200)
    plt.close()

    print(f"Gantt salvo em: {caminho}")

df = carregar_gantt(ARQUIVO_LOG)

plot_gantt(
    df,
    tipo="SCHED",
    titulo="Gantt original - solução do scheduling",
    arquivo_saida="gantt_01_sched_original.png"
)

df_conflitos = carregar_conflitos_txt(ARQUIVO_LOG)

gerar_txt_conflitos(
    df_conflitos,
    arquivo_saida="jobs_conflitantes.txt"
)

plot_gantt(
    df,
    tipo="FINAL",
    titulo="Gantt final - solução heurística viabilizada",
    arquivo_saida="gantt_03_final_viabilizado.png"
)

plot_gantt(
    df,
    tipo="FINAL_LUNCH",
    titulo="Gantt final - solução heurística viabilizada com almoço",
    arquivo_saida="gantt_04_final_lunch.png",
    include_lunch=True
)

print("\nArquivos gerados na pasta:", PASTA_SAIDA.resolve())