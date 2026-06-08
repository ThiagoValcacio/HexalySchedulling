import re
import pandas as pd
from datetime import datetime, timedelta


# ============================================================
# CONFIGURAÇÕES
# ============================================================

INPUT_PATH = "solucao.tsv"

OUTPUT_GANTT_PATH = "gantt_final_lunch.txt"

OUTPUT_FO_DETALHE_PATH = "funcao_objetivo_detalhe_agrupada.csv"
OUTPUT_FO_TOTAL_PATH = "funcao_objetivo_total.csv"

OUTPUT_EXECUCOES_DETALHE_PATH = "execucoes_detalhe.csv"

OUTPUT_HORA_EXTRA_JOB_PATH = "hora_extra_por_job.csv"
OUTPUT_HORA_EXTRA_MECANICO_PATH = "hora_extra_por_mecanico.csv"
OUTPUT_HORA_EXTRA_REAL_MECANICO_PATH = "hora_extra_real_por_mecanico.csv"

SLOT_MINUTES = 10
START_TIME = "09:00"

# 09:00 + 54 slots de 10 min = 18:00
SLOT_FIM_EXPEDIENTE = 54

TIPO_GANTT = "FINAL_LUNCH"

GERAR_QUEBRA_ALMOCO = True


# ============================================================
# FUNÇÕES AUXILIARES
# ============================================================

def slot_to_time(slot: int, start_time: str = START_TIME, slot_minutes: int = SLOT_MINUTES) -> str:
    base = datetime.strptime(start_time, "%H:%M")
    result = base + timedelta(minutes=int(slot) * slot_minutes)
    return result.strftime("%H:%M")


def normalizar_cliente(valor) -> str:
    if pd.isna(valor):
        return ""
    return str(valor).strip().lower()


def normalizar_job_base(job: str) -> str:
    """
    Remove sufixos finais do tipo -2, -3, -4 etc.

    Exemplos:
    GBR-4J85   -> GBR-4J85
    GBR-4J85-2 -> GBR-4J85
    GBR-4J85-3 -> GBR-4J85
    """

    job = str(job).strip()
    return re.sub(r"-\d+$", "", job)


def prioridade_tipo(tipo: str) -> int:
    """
    Hierarquia de especialidade:
    Motor > Revisao Rapida > Revisao
    """

    tipo = str(tipo).strip().lower()

    if tipo == "motor":
        return 3

    if tipo in ["revisao rapida", "revisao_rapida", "revisão rápida"]:
        return 2

    if tipo in ["revisao", "revisão"]:
        return 1

    return 0


def tipo_mais_forte(series_tipos: pd.Series) -> str:
    tipos = series_tipos.dropna().astype(str).unique().tolist()

    if not tipos:
        return ""

    return max(tipos, key=prioridade_tipo)


def juntar_intervalos(intervalos):
    """
    Recebe intervalos [inicio, fim) e junta sobreposições.

    Exemplo:
    [(0, 10), (8, 12), (20, 25)]
    vira:
    [(0, 12), (20, 25)]
    """

    if not intervalos:
        return []

    intervalos = sorted(intervalos)

    unidos = []
    atual_inicio, atual_fim = intervalos[0]

    for inicio, fim in intervalos[1:]:
        if inicio <= atual_fim:
            atual_fim = max(atual_fim, fim)
        else:
            unidos.append((atual_inicio, atual_fim))
            atual_inicio, atual_fim = inicio, fim

    unidos.append((atual_inicio, atual_fim))

    return unidos


def adicionar_linha_gantt(linhas, mecanico, job, inicio_idx, fim_idx, status):
    """
    A solução usa intervalo [início, fim), ou seja:
    - Slot início ocupa
    - Slot fim não ocupa

    Exemplo:
    início = 0, fim = 1 ocupa apenas o slot 0.

    Porém, o script do Gantt interpreta fim_idx como inclusivo,
    porque calcula:
    duracao = fim_idx - inicio_idx + 1

    Então, ao escrever o TXT:
    - inicio_idx_gantt = inicio_idx
    - fim_idx_gantt = fim_idx - 1
    - horário de início = slot_to_time(inicio_idx)
    - horário de fim = slot_to_time(fim_idx)
    """

    if fim_idx <= inicio_idx:
        return

    inicio_idx_gantt = int(inicio_idx)
    fim_idx_gantt = int(fim_idx) - 1

    linhas.append(
        f"GANTT;{TIPO_GANTT};{mecanico};{job};"
        f"{inicio_idx_gantt};{fim_idx_gantt};"
        f"{slot_to_time(inicio_idx)};{slot_to_time(fim_idx)};"
        f"{status}"
    )


def calcular_hora_extra_real_mecanico(grupo: pd.DataFrame) -> int:
    """
    Calcula a hora extra real do mecânico sem dupla contagem.

    Se houver dois jobs sobrepostos depois das 18h, os minutos sobrepostos
    são contados apenas uma vez.
    """

    intervalos = []

    for _, row in grupo.iterrows():
        inicio = int(row["Slot início"])
        fim = int(row["Slot fim"])

        inicio_extra = max(inicio, SLOT_FIM_EXPEDIENTE)
        fim_extra = fim

        if fim_extra > inicio_extra:
            intervalos.append((inicio_extra, fim_extra))

    if not intervalos:
        return 0

    intervalos_unidos = juntar_intervalos(intervalos)

    slots_extra = sum(fim - inicio for inicio, fim in intervalos_unidos)

    return slots_extra * SLOT_MINUTES


# ============================================================
# LEITURA DA BASE
# ============================================================

df = pd.read_csv(INPUT_PATH, sep="\t", encoding="utf-8-sig")

df.columns = [c.strip() for c in df.columns]

df["Mecânico"] = df["Mecânico"].astype(str).str.strip()
df["Job / placa"] = df["Job / placa"].astype(str).str.strip()

for col in ["Slot início", "Slot fim", "Rj - data chegada", "Tj"]:
    df[col] = pd.to_numeric(df[col], errors="coerce")


# ============================================================
# SEPARAÇÃO ENTRE JOBS E ALMOÇO
# ============================================================

df_jobs = df[df["Job / placa"].str.upper().str.strip() != "ALMOÇO"].copy()
df_lunch = df[df["Job / placa"].str.upper().str.strip() == "ALMOÇO"].copy()


# ============================================================
# CÁLCULO BASE DAS EXECUÇÕES
# ============================================================

df_jobs["p_j"] = df_jobs["Slot fim"] - df_jobs["Slot início"]

df_jobs["Tj_confere_pj"] = df_jobs["Tj"] == df_jobs["p_j"]

if not df_jobs["Tj_confere_pj"].all():
    inconsistencias_tj = df_jobs[~df_jobs["Tj_confere_pj"]][
        ["Mecânico", "Job / placa", "Slot início", "Slot fim", "Tj", "p_j"]
    ]

    print("Atenção: existem jobs em que Tj é diferente de p_j = Slot fim - Slot início.")
    print(inconsistencias_tj.to_string(index=False))

df_jobs["job_base"] = df_jobs["Job / placa"].apply(normalizar_job_base)


# ============================================================
# CÁLCULO DA FUNÇÃO OBJETIVO AGRUPADA POR JOB BASE
# ============================================================

registros_fo = []

for job_base, grupo in df_jobs.groupby("job_base"):
    grupo = grupo.copy()

    intervalos = [
        (int(row["Slot início"]), int(row["Slot fim"]))
        for _, row in grupo.iterrows()
    ]

    intervalos_unidos = juntar_intervalos(intervalos)

    primeiro_inicio = min(inicio for inicio, fim in intervalos)
    ultimo_fim = max(fim for inicio, fim in intervalos)

    processamento_soma_partes = sum(fim - inicio for inicio, fim in intervalos)

    processamento_real_sem_sobreposicao = sum(
        fim - inicio for inicio, fim in intervalos_unidos
    )

    fila_retorno = (
        ultimo_fim
        - primeiro_inicio
        - processamento_real_sem_sobreposicao
    )

    rjs = grupo["Rj - data chegada"].dropna().unique()

    if len(rjs) == 0:
        rj = 0
    else:
        rj = min(rjs)

    if len(rjs) > 1:
        print(
            f"Atenção: job {job_base} tem mais de um Rj. "
            f"Usando o menor Rj: {rj}. Valores encontrados: {list(rjs)}"
        )

    cliente = (
        grupo["Cliente?"]
        .apply(normalizar_cliente)
        .eq("sim")
        .any()
    )

    cliente_txt = "Sim" if cliente else "Não"

    if cliente:
        base_time = rj
    else:
        base_time = 0.5 * rj

    completion = ultimo_fim

    fo_job = completion - base_time

    fo_reconstruida = (
        primeiro_inicio
        - base_time
        + processamento_real_sem_sobreposicao
        + fila_retorno
    )

    registros_fo.append({
        "job_base": job_base,
        "tipo_mais_forte": tipo_mais_forte(grupo["Tipo"]),
        "cliente": cliente_txt,
        "rj": rj,
        "primeiro_inicio": primeiro_inicio,
        "ultimo_fim": ultimo_fim,
        "completion": completion,
        "base_time": base_time,
        "processamento_soma_partes": processamento_soma_partes,
        "processamento_real_sem_sobreposicao": processamento_real_sem_sobreposicao,
        "fila_retorno": fila_retorno,
        "fo_job": fo_job,
        "fo_reconstruida": fo_reconstruida,
        "qtd_partes": len(grupo),
        "partes": ", ".join(grupo["Job / placa"].astype(str).tolist()),
        "mecanicos": ", ".join(sorted(grupo["Mecânico"].astype(str).unique().tolist())),
    })

df_fo_agrupada = pd.DataFrame(registros_fo).sort_values("job_base")

fo_total = df_fo_agrupada["fo_job"].sum()

df_fo_total = pd.DataFrame([{
    "fo_total_agrupada": fo_total,
    "n_jobs_agrupados": len(df_fo_agrupada),
}])

print(f"FO total agrupada = {fo_total}")

print("\nDetalhe da FO agrupada por job:")
print(
    df_fo_agrupada[
        [
            "job_base",
            "tipo_mais_forte",
            "cliente",
            "rj",
            "primeiro_inicio",
            "ultimo_fim",
            "processamento_real_sem_sobreposicao",
            "fila_retorno",
            "base_time",
            "fo_job",
            "qtd_partes",
        ]
    ].to_string(index=False)
)


# ============================================================
# CÁLCULO DE HORA EXTRA
# ============================================================

df_jobs["slots_hora_extra"] = df_jobs.apply(
    lambda row: max(
        0,
        row["Slot fim"] - max(row["Slot início"], SLOT_FIM_EXPEDIENTE)
    ),
    axis=1
)

df_jobs["minutos_hora_extra"] = df_jobs["slots_hora_extra"] * SLOT_MINUTES

hora_extra_por_job = df_jobs[df_jobs["minutos_hora_extra"] > 0][
    [
        "Mecânico",
        "Job / placa",
        "job_base",
        "Slot início",
        "Slot fim",
        "p_j",
        "slots_hora_extra",
        "minutos_hora_extra",
    ]
].copy()

hora_extra_por_mecanico = (
    df_jobs
    .groupby("Mecânico", as_index=False)["minutos_hora_extra"]
    .sum()
    .rename(columns={"minutos_hora_extra": "minutos_hora_extra_total"})
    .sort_values("Mecânico")
)

hora_extra_total = df_jobs["minutos_hora_extra"].sum()

registros_hora_extra_real = []

for mecanico, grupo in df_jobs.groupby("Mecânico"):
    registros_hora_extra_real.append({
        "Mecânico": mecanico,
        "minutos_hora_extra_real": calcular_hora_extra_real_mecanico(grupo)
    })

hora_extra_real_por_mecanico = (
    pd.DataFrame(registros_hora_extra_real)
    .sort_values("Mecânico")
)

hora_extra_real_total = hora_extra_real_por_mecanico["minutos_hora_extra_real"].sum()

print("\nHora extra por job:")
if hora_extra_por_job.empty:
    print("Nenhum job com hora extra.")
else:
    print(hora_extra_por_job.to_string(index=False))

print("\nHora extra por mecânico:")
print(hora_extra_por_mecanico.to_string(index=False))

print(f"\nHora extra total por job: {hora_extra_total} minutos")

print("\nHora extra real por mecânico, sem dupla contagem de sobreposição:")
print(hora_extra_real_por_mecanico.to_string(index=False))

print(f"\nHora extra real total: {hora_extra_real_total} minutos")


# ============================================================
# EXPORTAÇÃO DOS RESULTADOS
# ============================================================

df_fo_agrupada.to_csv(
    OUTPUT_FO_DETALHE_PATH,
    index=False,
    encoding="utf-8-sig"
)

df_fo_total.to_csv(
    OUTPUT_FO_TOTAL_PATH,
    index=False,
    encoding="utf-8-sig"
)

cols_execucoes_detalhe = [
    "Mecânico",
    "Job / placa",
    "job_base",
    "Slot início",
    "Slot fim",
    "p_j",
    "Tj",
    "Tj_confere_pj",
    "Tipo",
    "Cliente?",
    "Rj - data chegada",
    "slots_hora_extra",
    "minutos_hora_extra",
]

df_jobs[cols_execucoes_detalhe].to_csv(
    OUTPUT_EXECUCOES_DETALHE_PATH,
    index=False,
    encoding="utf-8-sig"
)

hora_extra_por_job.to_csv(
    OUTPUT_HORA_EXTRA_JOB_PATH,
    index=False,
    encoding="utf-8-sig"
)

hora_extra_por_mecanico.to_csv(
    OUTPUT_HORA_EXTRA_MECANICO_PATH,
    index=False,
    encoding="utf-8-sig"
)

hora_extra_real_por_mecanico.to_csv(
    OUTPUT_HORA_EXTRA_REAL_MECANICO_PATH,
    index=False,
    encoding="utf-8-sig"
)


# ============================================================
# GERAÇÃO DO TXT DO GANTT
# ============================================================

linhas_gantt = [
    "GANTT;tipo;mecanico;job;inicio_idx;fim_idx;inicio;fim;status"
]

ordem_mecanicos = df["Mecânico"].dropna().drop_duplicates().tolist()

for mecanico in ordem_mecanicos:
    lunch_mec = df_lunch[df_lunch["Mecânico"] == mecanico]
    jobs_mec = df_jobs[df_jobs["Mecânico"] == mecanico].copy()

    jobs_mec = jobs_mec.sort_values(
        by=["Slot início", "Slot fim", "Job / placa"]
    )

    lunch_inicio = None
    lunch_fim = None

    if not lunch_mec.empty:
        lunch_row = lunch_mec.iloc[0]

        lunch_inicio = int(lunch_row["Slot início"])
        lunch_fim = int(lunch_row["Slot fim"])

        adicionar_linha_gantt(
            linhas=linhas_gantt,
            mecanico=mecanico,
            job="Almoco",
            inicio_idx=lunch_inicio,
            fim_idx=lunch_fim,
            status="almoco",
        )

    for _, row in jobs_mec.iterrows():
        job = row["Job / placa"]
        inicio = int(row["Slot início"])
        fim = int(row["Slot fim"])

        if not GERAR_QUEBRA_ALMOCO or lunch_inicio is None:
            adicionar_linha_gantt(
                linhas=linhas_gantt,
                mecanico=mecanico,
                job=job,
                inicio_idx=inicio,
                fim_idx=fim,
                status="viabilizado",
            )
            continue

        cruza_almoco = inicio < lunch_fim and fim > lunch_inicio

        if not cruza_almoco:
            adicionar_linha_gantt(
                linhas=linhas_gantt,
                mecanico=mecanico,
                job=job,
                inicio_idx=inicio,
                fim_idx=fim,
                status="viabilizado",
            )
        else:
            if inicio < lunch_inicio:
                adicionar_linha_gantt(
                    linhas=linhas_gantt,
                    mecanico=mecanico,
                    job=f"{job}_parte_1",
                    inicio_idx=inicio,
                    fim_idx=min(fim, lunch_inicio),
                    status="quebrado_antes_almoco",
                )

            if fim > lunch_fim:
                adicionar_linha_gantt(
                    linhas=linhas_gantt,
                    mecanico=mecanico,
                    job=f"{job}_parte_2",
                    inicio_idx=max(inicio, lunch_fim),
                    fim_idx=fim,
                    status="quebrado_depois_almoco",
                )

with open(OUTPUT_GANTT_PATH, "w", encoding="utf-8") as f:
    f.write("\n".join(linhas_gantt))


# ============================================================
# CHECAGENS DE VIABILIDADE
# ============================================================

jobs_antes_rj = df_jobs[df_jobs["Slot início"] < df_jobs["Rj - data chegada"]].copy()

if not jobs_antes_rj.empty:
    print("\nAtenção: existem jobs começando antes do Rj.")
    print(
        jobs_antes_rj[
            ["Mecânico", "Job / placa", "Slot início", "Rj - data chegada", "Slot fim"]
        ].to_string(index=False)
    )


conflitos = []

for mecanico, grupo in df_jobs.groupby("Mecânico"):
    grupo = grupo.sort_values(["Slot início", "Slot fim"])

    job_anterior = None
    inicio_anterior = None
    fim_anterior = None

    for _, row in grupo.iterrows():
        job_atual = row["Job / placa"]
        inicio_atual = int(row["Slot início"])
        fim_atual = int(row["Slot fim"])

        if fim_anterior is not None and inicio_atual < fim_anterior:
            conflitos.append({
                "Mecânico": mecanico,
                "Job anterior": job_anterior,
                "Início anterior": inicio_anterior,
                "Fim anterior": fim_anterior,
                "Job atual": job_atual,
                "Início atual": inicio_atual,
                "Fim atual": fim_atual,
            })

        if fim_anterior is None or fim_atual > fim_anterior:
            job_anterior = job_atual
            inicio_anterior = inicio_atual
            fim_anterior = fim_atual

if conflitos:
    print("\nAtenção: existem sobreposições entre jobs do mesmo mecânico.")
    print(pd.DataFrame(conflitos).to_string(index=False))


# ============================================================
# RESUMO FINAL
# ============================================================

print("\nArquivos gerados:")
print(OUTPUT_GANTT_PATH)
print(OUTPUT_FO_DETALHE_PATH)
print(OUTPUT_FO_TOTAL_PATH)
print(OUTPUT_EXECUCOES_DETALHE_PATH)
print(OUTPUT_HORA_EXTRA_JOB_PATH)
print(OUTPUT_HORA_EXTRA_MECANICO_PATH)
print(OUTPUT_HORA_EXTRA_REAL_MECANICO_PATH)