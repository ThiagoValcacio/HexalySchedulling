import math
import gurobipy as gp
from gurobipy import GRB


def normalize_speciality(s: str) -> str:
    if s == "Revisao_Rapida":
        return "Revisao Rapida"
    return s


def read_instance_txt(file_path: str):
    with open(file_path, "r", encoding="utf-8") as f:
        tokens = f.read().split()

    idx = 0

    def read_token(expected=None):
        nonlocal idx

        if idx >= len(tokens):
            raise ValueError("Fim do arquivo alcançado antes do esperado.")

        token = tokens[idx]
        idx += 1

        if expected is not None and token != expected:
            raise ValueError(f"Esperado '{expected}', encontrado '{token}'.")

        return token

    read_token("START_UNIX")
    t_input_start_unix = float(read_token())

    read_token("END_UNIX")
    t_input_end_unix = float(read_token())

    read_token("N_TASKS")
    n_tasks = int(read_token())

    read_token("TASKS")

    tasks = []
    t_processing_time = {}
    k_speciality_tasks = {}
    t_hour_arrived_job_unix = {}
    k_task_type = {}

    for _ in range(n_tasks):
        task = read_token()
        processing_time = float(read_token())
        speciality = normalize_speciality(read_token())
        arrival_unix = float(read_token())
        task_type = read_token()

        tasks.append(task)
        t_processing_time[task] = processing_time
        k_speciality_tasks[task] = speciality
        t_hour_arrived_job_unix[task] = arrival_unix
        k_task_type[task] = task_type

    read_token("N_MECHANICS")
    n_mechanics = int(read_token())

    read_token("MECHANICS")

    mechanics = []
    b_available_mechanic = {}
    k_speciality_mechanics = {}

    for _ in range(n_mechanics):
        mechanic = read_token()
        available = int(read_token())
        speciality = normalize_speciality(read_token())

        mechanics.append(mechanic)
        b_available_mechanic[mechanic] = available == 1
        k_speciality_mechanics[mechanic] = speciality

    return {
        "tasks": tasks,
        "mechanics": mechanics,
        "t_input_start_unix": t_input_start_unix,
        "t_input_end_unix": t_input_end_unix,
        "t_processing_time": t_processing_time,
        "k_speciality_tasks": k_speciality_tasks,
        "t_hour_arrived_job_unix": t_hour_arrived_job_unix,
        "k_task_type": k_task_type,
        "b_available_mechanic": b_available_mechanic,
        "k_speciality_mechanics": k_speciality_mechanics,
    }


def format_hour(seconds_day: int) -> str:
    seconds_day = seconds_day % (24 * 60 * 60)

    h = seconds_day // 3600
    m = (seconds_day % 3600) // 60

    return f"{h:02d}:{m:02d}"


def is_compatible(esp_mec: str, esp_task: str) -> bool:
    if esp_mec == "Motor":
        return True

    if esp_mec == "Revisao":
        return esp_task != "Motor"

    if esp_mec == "Revisao Rapida":
        return esp_task == "Revisao Rapida"

    return False


def solve_gap_gurobi(dados, time_limit=60, mip_gap=None, verbose=True):
    mechanics = dados["mechanics"]
    tasks = dados["tasks"]

    t_processing_time = dados["t_processing_time"]
    k_speciality_tasks = dados["k_speciality_tasks"]
    k_speciality_mechanics = dados["k_speciality_mechanics"]
    t_hour_arrived_job_unix = dados["t_hour_arrived_job_unix"]
    t_input_start_unix = dados["t_input_start_unix"]
    t_input_end_unix = dados["t_input_end_unix"]

    # =========================
    # Compatibilidade
    # =========================

    b_compatible = {}

    for m in mechanics:
        for j in tasks:
            b_compatible[m, j] = is_compatible(
                esp_mec=k_speciality_mechanics[m],
                esp_task=k_speciality_tasks[j]
            )

    # =========================
    # Parâmetros de tempo
    # =========================

    n_seconds_day = 24 * 60 * 60
    n_seconds_slot = 10 * 60
    n_timezone_offset_seconds = -3 * 60 * 60

    t_start_unix_int = math.floor(t_input_start_unix)
    t_end_unix_int = math.floor(t_input_end_unix)

    t_start_day_seconds = (
        t_start_unix_int
        + n_timezone_offset_seconds
        + n_seconds_day
    ) % n_seconds_day

    t_end_day_seconds = (
        t_end_unix_int
        + n_timezone_offset_seconds
        + n_seconds_day
    ) % n_seconds_day

    n_duration_seconds = t_end_day_seconds - t_start_day_seconds
    n_total_slots = math.floor(n_duration_seconds / n_seconds_slot)

    hours = {
        t: format_hour(t_start_day_seconds + t * n_seconds_slot)
        for t in range(n_total_slots)
    }

    n_mechanicslots = n_total_slots
    n_mechanicslots_gap = n_total_slots - 6

    t_time_processing_opt = {}
    n_slots_arrival_job = {}

    for j in tasks:
        t_time_processing_opt[j] = math.ceil(t_processing_time[j] / 10)

        t_arrived_job_unix_int = math.floor(t_hour_arrived_job_unix[j])

        t_arrived_job_seconds = (
            t_arrived_job_unix_int
            + n_timezone_offset_seconds
            + n_seconds_day
        ) % n_seconds_day

        if t_start_day_seconds < t_arrived_job_seconds:
            t_arrival_since_start = t_arrived_job_seconds - t_start_day_seconds
        else:
            t_arrival_since_start = 0

        n_slots_arrival_job[j] = math.floor(t_arrival_since_start / n_seconds_slot)

    # =========================
    # Validação básica
    # =========================

    for j in tasks:
        qtd_compativeis = sum(
            1 for m in mechanics
            if b_compatible[m, j]
        )

        if qtd_compativeis == 0:
            raise ValueError(f"Task sem mecânico compatível: {j}")

    # =========================
    # Modelo
    # =========================

    model = gp.Model("gap_assignment_from_txt")

    if not verbose:
        model.Params.OutputFlag = 0

    if time_limit is not None:
        model.Params.TimeLimit = time_limit

    if mip_gap is not None:
        model.Params.MIPGap = mip_gap

    # =========================
    # Variáveis
    # =========================

    x = {}

    for m in mechanics:
        for j in tasks:
            if b_compatible[m, j]:
                x[m, j] = model.addVar(
                    vtype=GRB.BINARY,
                    name=f"B_ASSIGNMENT[{m},{j}]"
                )

    model.update()

    # =========================
    # Carga
    # =========================

    load = {}

    for m in mechanics:
        load[m] = gp.quicksum(
            t_time_processing_opt[j] * x[m, j]
            for j in tasks
            if b_compatible[m, j]
        )

    # =========================
    # Capacidade
    # =========================

    for m in mechanics:
        model.addConstr(
            load[m] <= n_mechanicslots_gap,
            name=f"Restricao_capacidade_{m}"
        )

    # =========================
    # Atribuição obrigatória
    # =========================

    for j in tasks:
        model.addConstr(
            gp.quicksum(
                x[m, j]
                for m in mechanics
                if b_compatible[m, j]
            ) == 1,
            name=f"Atribuicao_obrigatoria_{j}"
        )

    # =========================
    # Função objetivo ativa do seu CFW
    # =========================

    obj = gp.quicksum(
        t_time_processing_opt[j] * x[m, j]
        - t_time_processing_opt[q] * x[m, q]
        for j in tasks
        for q in tasks
        if j != q
        for m in mechanics
        if b_compatible[m, j] and b_compatible[m, q]
    )

    model.setObjective(obj, GRB.MINIMIZE)

    # =========================
    # Otimizar
    # =========================

    model.optimize()

    # =========================
    # Pós-solução
    # =========================

    assignment = {}

    if model.Status == GRB.OPTIMAL:
        print("\nStatus: OPTIMAL")

    elif model.Status == GRB.TIME_LIMIT:
        print("\nStatus: TIME_LIMIT")

    elif model.Status == GRB.INFEASIBLE:
        print("\nStatus: INFEASIBLE")
        model.computeIIS()
        model.write("modelo_inviavel.ilp")
        print("Arquivo IIS gerado: modelo_inviavel.ilp")
        return None

    else:
        print(f"\nStatus Gurobi: {model.Status}")
        return None

    print(f"Objetivo: {model.ObjVal}")
    print(f"Capacidade por mecânico: {n_mechanicslots_gap} slots")
    print()

    print("ALOCAÇÕES")
    for j in tasks:
        for m in mechanics:
            if b_compatible[m, j]:
                value = x[m, j].X
                assignment[m, j] = value

                if value > 0.5:
                    print(f"Mecanico: {m} | Task: {j} | Valor: 1")
            else:
                assignment[m, j] = 0

    print()
    print("CARGA POR MECÂNICO")
    for m in mechanics:
        carga = sum(
            t_time_processing_opt[j] * assignment[m, j]
            for j in tasks
            if b_compatible[m, j]
        )

        print(f"{m}: {carga} slots")

    return {
        "model": model,
        "assignment": assignment,
        "b_compatible": b_compatible,
        "t_time_processing_opt": t_time_processing_opt,
        "n_slots_arrival_job": n_slots_arrival_job,
        "n_total_slots": n_total_slots,
        "n_mechanicslots_gap": n_mechanicslots_gap,
        "hours": hours,
    }


if __name__ == "__main__":

    dados = read_instance_txt("instancias/Inst_02.txt")

    resultado = solve_gap_gurobi(
        dados=dados,
        time_limit=60,
        mip_gap=0.01,
        verbose=True
    )