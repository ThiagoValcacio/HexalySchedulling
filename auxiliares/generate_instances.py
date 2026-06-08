from datetime import datetime, date, time
from zoneinfo import ZoneInfo
import random
import math


SPECIALTIES = ["Revisao", "Revisao_Rapida", "Motor"]
DATA_BASE_PADRAO = date(2026, 5, 18)


def to_unix_seconds(dt: datetime) -> int:
    return int(dt.timestamp())


def sortear_duracao_ponderada(
    duracao_min: int,
    duracao_max: int,
    ponderador: float = 3.0
) -> int:
    """
    Sorteia uma duração mais concentrada perto do limite inferior.

    ponderador = 1.0  -> quase uniforme
    ponderador = 3.0  -> mais peso perto do mínimo
    ponderador = 5.0+ -> muito concentrado perto do mínimo
    """

    if ponderador <= 0:
        raise ValueError("ponderador deve ser maior que zero.")

    fator = random.betavariate(1, ponderador)

    duracao = duracao_min + fator * (duracao_max - duracao_min)

    return round(duracao)

def gerar_tasks_validas(
    n_tasks: int,
    duracao_min: int,
    duracao_max: int,
    ponderador_duracao: float,
    tipos_tasks: list[str],
    start_unix: int,
    end_unix: int,
    slot_minutos: int,
    capacidade_total_slots: int,
    capacidade_motor_slots: int,
    max_tentativas: int = 10000
) -> list[dict]:

    demanda_minima_slots = n_tasks * math.ceil(duracao_min / slot_minutos)

    if demanda_minima_slots > capacidade_total_slots:
        raise ValueError(
            "Instância inviável: mesmo usando a duração mínima, "
            "a demanda total dos jobs excede a capacidade total dos mecânicos. "
            f"Demanda mínima: {demanda_minima_slots} slots | "
            f"Capacidade total: {capacidade_total_slots} slots"
        )

    for tentativa in range(max_tentativas):

        tasks = []
        demanda_total_slots = 0
        demanda_motor_slots = 0

        for i in range(1, n_tasks + 1):
            nome_task = f"Task{i}"

            duracao = sortear_duracao_ponderada(
                duracao_min=duracao_min,
                duracao_max=duracao_max,
                ponderador=ponderador_duracao
            )

            duracao_slots = math.ceil(duracao / slot_minutos)

            especialidade = definir_especialidade_task(duracao)

            demanda_total_slots += duracao_slots

            if especialidade == "Motor":
                demanda_motor_slots += duracao_slots

            tipo = tipos_tasks[i - 1]

            if tipo == "Interna":
                chegada_unix = start_unix
            else:
                chegada_unix = sortear_chegada_valida(
                    start_unix=start_unix,
                    end_unix=end_unix,
                    duracao_minutos=duracao,
                    slot_minutos=slot_minutos
                )

            tasks.append({
                "nome": nome_task,
                "duracao": duracao,
                "especialidade": especialidade,
                "chegada_unix": chegada_unix,
                "tipo": tipo
            })

        if (
            demanda_total_slots <= capacidade_total_slots
            and demanda_motor_slots <= capacidade_motor_slots
        ):
            tasks.sort(key=lambda x: x["chegada_unix"])
            return tasks

    raise ValueError(
        "Não foi possível gerar uma instância viável dentro do número máximo "
        f"de tentativas ({max_tentativas}). "
        "Reduza n_tasks, reduza duracao_max, aumente n_mecanicos, "
        "aumente a proporção de mecânicos Motor ou aumente o ponderador."
    )

def definir_especialidade_task(duracao: int) -> str:
    """
    Regra:
    - Até 50 min: Revisao_Rapida
    - Acima de 50 min: Revisao ou Motor
    """

    if duracao <= 60:
        return "Revisao_Rapida"

    return random.choice(["Revisao", "Motor"])


def calcular_qtd_por_proporcao(n_total: int, proporcoes: dict[str, float]) -> dict[str, int]:
    """
    Converte proporções em quantidades inteiras, garantindo que a soma final
    seja exatamente igual a n_total.
    """

    valores_exatos = {
        k: n_total * v
        for k, v in proporcoes.items()
    }

    quantidades = {
        k: math.floor(v)
        for k, v in valores_exatos.items()
    }

    faltantes = n_total - sum(quantidades.values())

    restos = sorted(
        proporcoes.keys(),
        key=lambda k: valores_exatos[k] - quantidades[k],
        reverse=True
    )

    for i in range(faltantes):
        quantidades[restos[i]] += 1

    return quantidades


def sortear_especialidades_mecanicos(n_mecanicos: int) -> list[str]:
    """
    Proporção dos mecânicos:
    - 20% Motor
    - 15% Revisao_Rapida
    - 65% Revisao
    """

    proporcoes = {
        "Motor": 0.25,
        "Revisao_Rapida": 0.15,
        "Revisao": 0.60
    }

    quantidades = calcular_qtd_por_proporcao(n_mecanicos, proporcoes)

    especialidades = []

    for especialidade, quantidade in quantidades.items():
        especialidades.extend([especialidade] * quantidade)

    random.shuffle(especialidades)

    return especialidades


def sortear_tipos_tasks(
    n_tasks: int,
    proporcao_interna_min: float,
    proporcao_interna_max: float
) -> list[str]:

    if proporcao_interna_min > proporcao_interna_max:
        raise ValueError("proporcao_interna_min não pode ser maior que proporcao_interna_max.")

    if not 0 <= proporcao_interna_min <= 1:
        raise ValueError("proporcao_interna_min deve estar entre 0 e 1.")

    if not 0 <= proporcao_interna_max <= 1:
        raise ValueError("proporcao_interna_max deve estar entre 0 e 1.")

    min_internas = math.ceil(n_tasks * proporcao_interna_min)
    max_internas = math.floor(n_tasks * proporcao_interna_max)

    if min_internas > max_internas:
        raise ValueError(
            "Intervalo inviável para a quantidade de tasks. "
            "Ajuste a proporção mínima/máxima ou aumente o número de tasks."
        )

    n_internas = random.randint(min_internas, max_internas)
    n_clientes = n_tasks - n_internas

    tipos = ["Interna"] * n_internas + ["Cliente"] * n_clientes
    random.shuffle(tipos)

    return tipos


def sortear_chegada_valida(
    start_unix: int,
    end_unix: int,
    duracao_minutos: int,
    slot_minutos: int = 10,
    intensidade_picos: float = 2.5,
    potencia_picos: float = 5
) -> int:
    """
    Sorteia a chegada com maior concentração no início e no fim da janela viável,
    e menor concentração no meio do dia.

    intensidade_picos:
    - 0.0 -> distribuição uniforme
    - 2.0 -> leve concentração nas extremidades
    - 4.0 -> concentração moderada
    - 8.0 -> concentração forte

    potencia_picos:
    - controla o formato da curva.
    - valores maiores deixam o meio mais baixo e as pontas mais fortes.
    """

    duracao_segundos = duracao_minutos * 60
    ultimo_inicio_possivel = end_unix - duracao_segundos

    if ultimo_inicio_possivel < start_unix:
        raise ValueError(
            f"A duração de {duracao_minutos} minutos não cabe na janela de trabalho."
        )

    slot_segundos = slot_minutos * 60

    primeiro_slot = 0
    ultimo_slot = (ultimo_inicio_possivel - start_unix) // slot_segundos

    slots_possiveis = list(range(primeiro_slot, ultimo_slot + 1))

    if len(slots_possiveis) == 1:
        slot_sorteado = slots_possiveis[0]
        return start_unix + slot_sorteado * slot_segundos

    pesos = []

    for slot in slots_possiveis:
        posicao = slot / ultimo_slot if ultimo_slot > 0 else 0

        # distância em relação ao meio da janela
        # meio = 0
        # extremidades = 1
        distancia_extremo = abs(posicao - 0.5) * 2

        peso = 1 + intensidade_picos * (distancia_extremo ** potencia_picos)

        pesos.append(peso)

    slot_sorteado = random.choices(
        population=slots_possiveis,
        weights=pesos,
        k=1
    )[0]

    return start_unix + slot_sorteado * slot_segundos

def gerar_instancia_terminal(
    n_mecanicos: int,
    n_tasks: int,
    duracao_min: int,
    duracao_max: int,
    proporcao_interna_min: float,
    proporcao_interna_max: float,
    timezone: str = "America/Sao_Paulo",
    hora_inicio: int = 9,
    hora_fim: int = 18,
    slot_minutos: int = 10,
    ponderador_duracao: float = 3.0,
    seed: int | None = None
) -> None:

    if seed is not None:
        random.seed(seed)

    if n_mecanicos <= 0:
        raise ValueError("n_mecanicos deve ser maior que zero.")

    if n_tasks <= 0:
        raise ValueError("n_tasks deve ser maior que zero.")

    if duracao_min <= 0 or duracao_max <= 0:
        raise ValueError("As durações devem ser maiores que zero.")

    if duracao_min > duracao_max:
        raise ValueError("duracao_min não pode ser maior que duracao_max.")

    tz = ZoneInfo(timezone)

    dt_inicio = datetime.combine(DATA_BASE_PADRAO, time(hora_inicio, 0), tzinfo=tz)
    dt_fim = datetime.combine(DATA_BASE_PADRAO, time(hora_fim, 0), tzinfo=tz)

    start_unix = to_unix_seconds(dt_inicio)
    end_unix = to_unix_seconds(dt_fim)

    janela_minutos = int((end_unix - start_unix) / 60)

    if duracao_max > janela_minutos:
        raise ValueError(
            f"duracao_max={duracao_max} não cabe na janela de {janela_minutos} minutos."
        )

    tipos_tasks = sortear_tipos_tasks(
        n_tasks=n_tasks,
        proporcao_interna_min=proporcao_interna_min,
        proporcao_interna_max=proporcao_interna_max
    )

    especialidades_mecanicos = sortear_especialidades_mecanicos(n_mecanicos)
    n_total_slots = janela_minutos // slot_minutos
    capacidade_por_mecanico_slots = n_total_slots - 6

    capacidade_total_slots = n_mecanicos * capacidade_por_mecanico_slots

    n_mecanicos_motor = especialidades_mecanicos.count("Motor")
    capacidade_motor_slots = n_mecanicos_motor * capacidade_por_mecanico_slots

    tasks = gerar_tasks_validas(
        n_tasks=n_tasks,
        duracao_min=duracao_min,
        duracao_max=duracao_max,
        ponderador_duracao=ponderador_duracao,
        tipos_tasks=tipos_tasks,
        start_unix=start_unix,
        end_unix=end_unix,
        slot_minutos=slot_minutos,
        capacidade_total_slots=capacidade_total_slots,
        capacidade_motor_slots=capacidade_motor_slots
    )

    print(f"START_UNIX {start_unix}")
    print(f"END_UNIX {end_unix}")
    print()

    print(f"N_TASKS {n_tasks}")
    print("TASKS")

    for task in tasks:
        print(
            f'{task["nome"]} '
            f'{task["duracao"]} '
            f'{task["especialidade"]} '
            f'{task["chegada_unix"]} '
            f'{task["tipo"]}'
        )

    print()
    print(f"N_MECHANICS {n_mecanicos}")
    print("MECHANICS")

    for i in range(1, n_mecanicos + 1):
        nome_mecanico = f"Mecanico{i}"
        disponivel = 1
        especialidade = especialidades_mecanicos[i - 1]

        print(f"{nome_mecanico} {disponivel} {especialidade}")

    demanda_total_slots = sum(
        math.ceil(task["duracao"] / slot_minutos)
        for task in tasks
    )

    demanda_motor_slots = sum(
        math.ceil(task["duracao"] / slot_minutos)
        for task in tasks
        if task["especialidade"] == "Motor"
    )

    print()
    print()
    print(f"# DEMANDA_TOTAL_SLOTS {demanda_total_slots}")
    print(f"# CAPACIDADE_TOTAL_SLOTS {capacidade_total_slots}")
    print(f"# N_MECANICOS_MOTOR {n_mecanicos_motor}")
    print(f"# DEMANDA_MOTOR_SLOTS {demanda_motor_slots}")
    print(f"# CAPACIDADE_MOTOR_SLOTS {capacidade_motor_slots}")
    print()


if __name__ == "__main__":

    gerar_instancia_terminal(
        n_mecanicos=10,
        n_tasks=30,
        duracao_min=25,
        duracao_max=400,
        proporcao_interna_min=0.10,
        proporcao_interna_max=0.45,
        ponderador_duracao=2.5,
        seed=None
    )