use cfw;
use math;
use hexaly;
use gap as gap;
use schedulling as sh;
use lunch as lch;
use random;

function solve(ls) { 
    ls.solve();

    if (ls.solution.status == "INCONSISTENT") {
        iis = ls.computeInconsistency();
        println(iis);
    }
    _solveStatus = ls.solution.status;
    return true;
}

function computeHeuristicObj(m) {
    local obj_value = 0;

    for[j in S_JOBS_MECHANIC[m]][t in 0...HORIZON_EXTRA : B_ASSIGNMENT_MEC_SCHED_OPT[m][j][gap.Hours[t]]] {
        obj_value += 
            t 
            + gap.t_time_processing_opt[j] 
            - (sh.b_type_task_client[j] ? gap.n_slots_arrival_job[j] : t);
    }

    return obj_value;
}

function main() {
    rng = random.create(42);
    cfw.init();
    _solveStatus = "INFEASIBLE";
   
    with (ls = hexaly.create()) {
        gap.run(ls);
        _solveStatus = gap._solveStatus;
    }

    if (_solveStatus == "INFEASIBLE" || _solveStatus == "INCONSISTENT") {
        println();
        println("NAO FOI POSSIVEL ENCONTRAR SOLUCAO VIAVEL");
        return;
    }
    
    println();
    for[j in cfw.Tasks] {
        if (gap.SLACK_ASSIGN_OPT[j] > 0) {
            println("Task ", j, " nao foi possivel ser realizada");
        }
    }

    local total_excess = sum[j in cfw.Tasks](gap.SLACK_ASSIGN_OPT[j]);
    if (total_excess > 0) {
        println();
        println("Carga total Excedida. Erro.");
        println();
        return;
    }

    S_JOBS_MECHANIC[m in cfw.Mechanics] = {};

    for[m in cfw.Mechanics][j in cfw.Tasks : gap.B_ASSIGNMENT_OPT[m][j]] {
        S_JOBS_MECHANIC[m].add(j);
        // {Mecanico 1 : {}, Mecanico 2 : {Task 1}, Mecanico 3 : {Task 2, Task 3}}
    }

    B_ASSIGNMENT_OPT_HEURISTIC[m in cfw.Mechanics][j in cfw.Tasks] = false;

    for[m in cfw.Mechanics][j in cfw.Tasks] {
        B_ASSIGNMENT_OPT_HEURISTIC[m][j] = gap.B_ASSIGNMENT_OPT[m][j];
    }

    LB_SCHED[m in cfw.Mechanics] = nil;
    UB_SCHED[m in cfw.Mechanics] = nil;
    STATUS_SCHED[m in cfw.Mechanics] = nil;

    GAP_ASSIGN_MEC_OPT[m in cfw.Mechanics][j in cfw.Tasks] = 0;

    HORIZON_EXTRA = gap.n_mechanicslots + 40;
    for[m in cfw.Mechanics][j in cfw.Tasks][t in 0...HORIZON_EXTRA] {
        B_ASSIGNMENT_MEC_SCHED_OPT[m][j][gap.Hours[t]] = false;
    }

    warm_start = false;
    contador = 0;


    while (contador < 1) {
        contador += 1;

        B_ASSIGNMENT_MEC_SCHED_INITIAL[m in cfw.Mechanics][j in cfw.Tasks][h in gap.Hours] = false;
        GAP_ASSIGN_INITIAL[m in cfw.Mechanics][j in cfw.Tasks] = 0;

        for[m in cfw.Mechanics] {            
            with (ls = hexaly.create()) {
                sh.run(ls, m, S_JOBS_MECHANIC[m], LB_SCHED[m], UB_SCHED[m], warm_start, WARM_START_SCHED);
                _solveStatus = sh._solveStatus;
                STATUS_SCHED[m] = sh._solveStatus;

                if (sh._obj_value != nil) {
                    LB_SCHED[m] = 0 + sh._obj_value;
                } else {
                    LB_SCHED[m] = nil;
                }
            }

            for[j in S_JOBS_MECHANIC[m]][t in 0...HORIZON_EXTRA] {
                B_ASSIGNMENT_MEC_SCHED_OPT[m][j][gap.Hours[t]] = false;
            }

            for[j in S_JOBS_MECHANIC[m]][t in 0...gap.n_mechanicslots] {
                B_ASSIGNMENT_MEC_SCHED_OPT[m][j][gap.Hours[t]] = sh.B_ASSIGNMENT_SCHED_OPT[j][gap.Hours[t]];
            }

            for[j in S_JOBS_MECHANIC[m]] {
                GAP_ASSIGN_MEC_OPT[m][j] = sh.GAP_ASSIGN_OPT[j];
            }

            if (_solveStatus == "INFEASIBLE" || _solveStatus == "INCONSISTENT") {
                println();
                println("NAO FOI POSSIVEL ENCONTRAR SOLUCAO VIAVEL");
                return;
            }
        }

        for[m in cfw.Mechanics][j in cfw.Tasks][t in 0...HORIZON_EXTRA] {
            B_ASSIGNMENT_MEC_SCHED_INITIAL[m][j][gap.Hours[t]] =
                B_ASSIGNMENT_MEC_SCHED_OPT[m][j][gap.Hours[t]];
        }

        for[m in cfw.Mechanics][j in cfw.Tasks] {
            GAP_ASSIGN_INITIAL[m][j] = GAP_ASSIGN_MEC_OPT[m][j];
        }

        println("GANTT;tipo;mecanico;job;inicio_idx;fim_idx;inicio;fim;status");

        for[m in cfw.Mechanics][j in S_JOBS_MECHANIC[m]][t in 0...HORIZON_EXTRA] {
            if (B_ASSIGNMENT_MEC_SCHED_INITIAL[m][j][gap.Hours[t]]) {

                local end_t_job = t + gap.t_time_processing_opt[j] - 1;

                if (end_t_job < HORIZON_EXTRA) {
                    println(
                        "GANTT;SCHED;",
                        m, ";",
                        j, ";",
                        t, ";",
                        end_t_job, ";",
                        gap.Hours[t], ";",
                        gap.Hours[end_t_job], ";",
                        "executado"
                    );
                }
            }
        }

        // Jobs conflitantes do scheduling
        println("CONFLITO_TXT;mecanico_original;job;chegada_idx;chegada;tempo_previsto_slots;tempo_previsto_min;especialidade");

        for[m in cfw.Mechanics][j in cfw.Tasks : GAP_ASSIGN_INITIAL[m][j] == 1] {

            local chegada_idx = gap.n_slots_arrival_job[j];
            local tempo_previsto_slots = gap.t_time_processing_opt[j];
            local tempo_previsto_min = tempo_previsto_slots * 10;

            println(
                "CONFLITO_TXT;",
                m, ";",
                j, ";",
                chegada_idx, ";",
                gap.Hours[chegada_idx], ";",
                tempo_previsto_slots, ";",
                tempo_previsto_min, ";",
                cfw.k_task_type[j]
            );
        }

        for[m in cfw.Mechanics] {
            UB_SCHED_HEURISTIC[m] = LB_SCHED[m];
        }

        TOTAL_LB = sum[m in cfw.Mechanics](LB_SCHED[m]) + sum[m in cfw.Mechanics][j in cfw.Tasks](GAP_ASSIGN_MEC_OPT[m][j] * gap.t_time_processing_opt[j]);
        TOTAL_UB = sum[m in cfw.Mechanics : UB_SCHED[m] != nil](UB_SCHED[m]);

        println(" ");
        println("LOWER BOUND SCHEDULLING: ", TOTAL_LB);
        println(" ");
        // Após resolver para todos os mecanicos, verificar qual possui inviabilidade

        m_inf = nil;
        found_infeasibility = false;
        println(" ");
        println("VERIFICANDO INVIABILIDADES...");

        for[m in cfw.Mechanics][j in S_JOBS_MECHANIC[m]: GAP_ASSIGN_MEC_OPT[m][j] == 1 && !found_infeasibility] {
            m_inf = m;
        }

        if (m_inf == nil) {
            println("TODOS OS MECANICOS FICARAM VIAVEIS.");
            println(" ");
            println("LOWER BOUND SCHEDULLING: ", TOTAL_LB);
            println(" ");
        }
        else
        {
            while (sum[m in cfw.Mechanics][j in cfw.Tasks](GAP_ASSIGN_MEC_OPT[m][j]) > 0) {

                println(" ");
                println("VERIFICANDO INVIABILIDADES...");

                found_infeasibility = false;
                for[m in cfw.Mechanics][j in S_JOBS_MECHANIC[m]: GAP_ASSIGN_MEC_OPT[m][j] > 0 && !found_infeasibility] {
                    m_inf = m;
                    println("INVIABILIDADE ENCONTRADA EM ", m);
                    println(" ");
                    found_infeasibility = true;
                }

                if (m_inf == nil) {
                    println("TODOS OS MECANICOS FICARAM VIAVEIS.");
                    println(" ");
                }
                else
                // verificar qual o job complicante
                {
                    println(" ");
                    println("ENCONTRANDO QUAL O JOB CONFLITANTE...");

                    job_conflicting = nil;
                    found_conflict = false;

                    for[j in S_JOBS_MECHANIC[m_inf] : !found_conflict && GAP_ASSIGN_MEC_OPT[m_inf][j] == 1] {
                        job_conflicting = j;
                        found_conflict = true;
                        println("JOB CONFLITANTE ENCONTRADO EM ", job_conflicting);
                        println(" ");
                    }

                    for[m in cfw.Mechanics][j in cfw.Tasks][t in 0...HORIZON_EXTRA] {
                        B_TOTAL_ASSIGNMENT[m][j][gap.Hours[t]] = false;
                    }

                    for[m in cfw.Mechanics][j in S_JOBS_MECHANIC[m]][t in 0...HORIZON_EXTRA] {
                        if (B_ASSIGNMENT_MEC_SCHED_OPT[m][j][gap.Hours[t]]) {
                            local end_t = t + gap.t_time_processing_opt[j] - 1;
                            if (end_t >= HORIZON_EXTRA) {
                                println("ERRO: job ultrapassa horizonte extra.");
                                println("Mecanico: ", m);
                                println("Job: ", j);
                                println("Inicio: ", gap.Hours[t]);
                                return;
                            }

                            for[t_ in t...(end_t + 1)] {
                                B_TOTAL_ASSIGNMENT[m][j][gap.Hours[t_]] = true;
                            }
                            // for[t_ in t...(t + gap.t_time_processing_opt[j])] {
                            //     B_TOTAL_ASSIGNMENT[m][j][gap.Hours[t_]] = true;
                            //     // println("Mecanico: ", m, " Job: ", j, " -> Slot: ", gap.Hours[t_], " com valor = ", B_ASSIGNMENT_MEC_SCHED_OPT[m][j][gap.Hours[t]]);
                            // }
                        }
                    }

                    for[m in cfw.Mechanics][t in 0...HORIZON_EXTRA] {
                        B_TOTAL_ASSIGNMENT_AGG[m][gap.Hours[t]] = sum[j in cfw.Tasks](B_TOTAL_ASSIGNMENT[m][j][gap.Hours[t]]);
                    }

                    println(" ");
                    println("ENCONTRANDO MECANICO CANDIDATO A RECEBER O JOB...");

                    // achar o mecanico que pode pegar esse job
                    // 1. ter compatibilidade 2. ter slots disponiveis depois da data de chegada do job na quantidade necessária

                    // mantém n_mechanicslots normal porque verifica se tem mecanico candidato para receber o job no tempo normal
                    count_false[m in cfw.Mechanics] = 0;
                    for[m in cfw.Mechanics : m != m_inf][t in gap.n_slots_arrival_job[job_conflicting]...gap.n_mechanicslots : gap.b_compatible[m][job_conflicting]] {

                        if (!B_TOTAL_ASSIGNMENT_AGG[m][gap.Hours[t]]) {
                            count_false[m] += 1;
                        }
                    }

                    mec_chose = nil;

                    // Primeiro: conta quantos mecânicos são candidatos
                    n_candidates = 0;
                    for[m in cfw.Mechanics] {
                        if (count_false[m] >= gap.t_time_processing_opt[job_conflicting]) {
                            n_candidates += 1;
                        }
                    }

                    hora_extra = false;

                    // Segundo: se existir candidato, sorteia um índice
                    if (n_candidates > 0) {
                        chosen_index = rng.next(0, n_candidates);
                        idx_candidate = 0;
                        found = false;
                        for[m in cfw.Mechanics : !found] {
                            if (count_false[m] >= gap.t_time_processing_opt[job_conflicting]) {
                                if (idx_candidate == chosen_index) {
                                    mec_chose = m;
                                    found = true;
                                    println("MECANICO CANDIDATO ENCONTRADO: ", mec_chose);
                                    println(" ");
                                }
                                idx_candidate += 1;
                            }
                        }
                    } else {
                        hora_extra = true;
                        println("NAO FOI POSSIVEL ENCONTRAR MECANICO CANDIDATO PARA REALOCAR O JOB CONFLITANTE ", job_conflicting);
                        println("O CUSTO SERA PENALIZADO COMO HORA EXTRA.");
                        // alocar no mecanico com mais slots livres de tras pra frente

                        ended_free_window[m in cfw.Mechanics] = false;
                        free_start[m in cfw.Mechanics] = nil;
                        last_period_free[m in cfw.Mechanics] = nil;

                        FREE_PERIODS_EXTRA[t in 0...HORIZON_EXTRA] = false;
                        count_false_extra[m in cfw.Mechanics] = 0;

                        for[m in cfw.Mechanics : gap.b_compatible[m][job_conflicting]] {
                            local stop = false;

                            for[k in 0...HORIZON_EXTRA : !stop] {
                                local t = HORIZON_EXTRA - 1 - k;

                                if (!B_TOTAL_ASSIGNMENT_AGG[m][gap.Hours[t]]) {
                                    count_false_extra[m] += 1;
                                } else {
                                    stop = true;
                                }
                            }
                        }

                        local max_free_slots = 0;
                        for [m in cfw.Mechanics : gap.b_compatible[m][job_conflicting]] {
                            // mec_chose_aux = m;
                            if (count_false_extra[m] > max_free_slots) {
                                max_free_slots = count_false_extra[m];
                                mec_chose = m;
                            }
                        }

                        // if (mec_chose == nil) {
                        //     mec_chose = mec_chose_aux;
                        // }

                        println("MECANICO ESCOLHIDO PARA ALOCAR O JOB CONFLITANTE: ", mec_chose, " POSSUI ", max_free_slots, " SLOTS LIVRES");

                        t_ajustado = HORIZON_EXTRA - max_free_slots;
                        stop = true;
                        println(" ");
                        println(job_conflicting, " DE TIPO ", cfw.k_task_type[job_conflicting], " ALOCADA COM SUCESSO PARA O ", mec_chose, " NO SLOT ", gap.Hours[t_ajustado]);
                        println("JOB ALOCADO: ", job_conflicting);
                        println("Mecanico: ", mec_chose);
                        println("Inicio: ", gap.Hours[t_ajustado]);
                        local end_job_conflicting = t_ajustado + gap.t_time_processing_opt[job_conflicting] - 1;
                        println("Fim: ", gap.Hours[end_job_conflicting]);
                        println(" ");
                        B_ASSIGNMENT_MEC_SCHED_OPT[mec_chose][job_conflicting][gap.Hours[t_ajustado]] = true;

                    }

                    if (!hora_extra) {

                        max_free_periods = 0;
                        count_periods = 0;

                        for[t in gap.n_slots_arrival_job[job_conflicting]...HORIZON_EXTRA] {
                            if (!B_TOTAL_ASSIGNMENT_AGG[mec_chose][gap.Hours[t]]) {
                                count_periods += 1;

                                if (count_periods > max_free_periods) {
                                    max_free_periods = count_periods;
                                }
                            } else {
                                count_periods = 0;
                            }
                        }

                        // tratativa para empurrar os jobs alocados para frente e abrir espaço para o job_conflicting
                        while (max_free_periods < gap.t_time_processing_opt[job_conflicting]) {

                            // se gap.n_slots_arrival_job[job_conflicting] for free:
                            // -> procure a proxima janela onde após ocupado, os slots voltam a ser free
                            // -> identificando, veja em qual t ele deixou de ser free
                            // -> essa distancia entre comecou a ser free na segunda vez e deixou de ser free é a quantidade que voce deve empurrar os jobs dentro do intervalo

                            // se gap.n_slots_arrival_job[job_conflicting] não for free:
                            // -> ajustar o arrival artificialmente para como sendo o primeiro periodo livre depois do arrival original

                            arrival_original = gap.n_slots_arrival_job[job_conflicting];
                            arrival = arrival_original;

                            if (B_TOTAL_ASSIGNMENT_AGG[mec_chose][gap.Hours[arrival]]) {
                                arrival = nil;
                                // Busca o primeiro slot livre a partir da chegada real do job
                                for[t in arrival_original...HORIZON_EXTRA : arrival == nil] {
                                    if (!B_TOTAL_ASSIGNMENT_AGG[mec_chose][gap.Hours[t]]) {
                                        arrival = t;
                                    }
                                }

                                if (arrival == nil) {
                                    println("ERRO: nao existe slot livre a partir do arrival original.");
                                    println("Mecanico: ", mec_chose);
                                    println("Job conflitante: ", job_conflicting);
                                    println("Arrival original: ", arrival_original);
                                    return;
                                }

                                println("Arrival original: ", arrival_original);
                                println("Arrival efetivo ajustado para primeiro slot livre: ", arrival);
                            }

                            // com o arrival artificial, com certeza vai ser livre o slot
                            if (!B_TOTAL_ASSIGNMENT_AGG[mec_chose][gap.Hours[arrival]]) {
                                // free
                                // procure a proxima janela onde após ocupado, os slots voltam a ser free
                                local slot_not_free = nil;
                                local break_flux = false;

                                for[t in arrival...HORIZON_EXTRA : !break_flux] {
                                    if (B_TOTAL_ASSIGNMENT_AGG[mec_chose][gap.Hours[t]]) {
                                        // ocupado, procurar a proxima janela onde volta a ser free
                                        slot_not_free = t;
                                        break_flux = true;
                                    }
                                }

                                local found_free_window = false;
                                local ended_free_window = false;
                                local free_start = nil;
                                local last_period_free = nil;

                                FREE_PERIODS[t in 0...HORIZON_EXTRA] = false;

                                if (slot_not_free == nil) {
                                    println("Nao existe bloco ocupado depois do arrival. Nao ha o que empurrar.");
                                    return;
                                }

                                for[t in slot_not_free...HORIZON_EXTRA : !ended_free_window] {

                                    if (!B_TOTAL_ASSIGNMENT_AGG[mec_chose][gap.Hours[t]]) {

                                        // achou ou continua a janela livre
                                        if (!found_free_window) {
                                            free_start = t;
                                            found_free_window = true;
                                        }

                                        FREE_PERIODS[t] = true;
                                        last_period_free = t;

                                    } else {

                                        // se já tinha achado a janela livre e voltou a ficar ocupado,
                                        // então terminou a janela
                                        if (found_free_window) {
                                            ended_free_window = true;
                                        }
                                    }
                                }

                                if (free_start == nil || last_period_free == nil) {
                                    println("ERRO: nao encontrou janela livre futura.");
                                    return;
                                }

                                local free_before = slot_not_free - arrival;
                                local slots_needed = gap.t_time_processing_opt[job_conflicting] - free_before;

                                if (slots_needed <= 0) {
                                    println("Ja existe espaco suficiente a partir do arrival.");
                                    return;
                                }

                                count_free = last_period_free - free_start + 1;

                                local deslocamento = min(count_free, slots_needed);

                                // empurrando os jobs alocados para frente
                                for[k in 0...HORIZON_EXTRA] {
                                    local t = HORIZON_EXTRA - 1 - k;
                                    // contagem de tras pra frente para nao sobrescrever os slots que ainda vou checar

                                    if (t >= arrival && t < free_start) {

                                        for[j in S_JOBS_MECHANIC[mec_chose]] {

                                            if (B_ASSIGNMENT_MEC_SCHED_OPT[mec_chose][j][gap.Hours[t]]) {

                                                local new_t = t + deslocamento;
                                                local end_t = new_t + gap.t_time_processing_opt[j] - 1;
                                                if (new_t >= HORIZON_EXTRA || end_t >= HORIZON_EXTRA) {
                                                    println("ERRO: deslocamento joga job para fora do horizonte.");
                                                    return;
                                                }

                                                B_ASSIGNMENT_MEC_SCHED_OPT[mec_chose][j][gap.Hours[t]] = false;
                                                B_ASSIGNMENT_MEC_SCHED_OPT[mec_chose][j][gap.Hours[new_t]] = true;
                                            }
                                        }
                                    }
                                }
                            } 

                            // Marcando e atualizando B_TOTAL_ASSIGNMENT novamente
                            for[m in cfw.Mechanics][j in cfw.Tasks][t in 0...HORIZON_EXTRA] {
                                B_TOTAL_ASSIGNMENT[m][j][gap.Hours[t]] = false;
                            }
                            for[m in cfw.Mechanics][j in cfw.Tasks][t in 0...HORIZON_EXTRA] {
                                if (B_ASSIGNMENT_MEC_SCHED_OPT[m][j][gap.Hours[t]]) {
                                    local end_t = t + gap.t_time_processing_opt[j] - 1;
                                    if (end_t >= HORIZON_EXTRA) {
                                        println("ERRO: job ultrapassa horizonte extra.");
                                        println("Mecanico: ", m);
                                        println("Job: ", j);
                                        println("Inicio: ", gap.Hours[t]);
                                        return;
                                    }

                                    for[t_ in t...(end_t + 1)] {
                                        B_TOTAL_ASSIGNMENT[m][j][gap.Hours[t_]] = true;
                                    }
                                    // for[t_ in t...(t + gap.t_time_processing_opt[j])] {
                                    //     B_TOTAL_ASSIGNMENT[m][j][gap.Hours[t_]] = true;
                                    //     // println("Mecanico: ", m, " Job: ", j, " -> Slot: ", gap.Hours[t_], " com valor = ", B_ASSIGNMENT_MEC_SCHED_OPT[m][j][gap.Hours[t]]);
                                    // }
                                }
                            }
                            for[m in cfw.Mechanics][t in 0...HORIZON_EXTRA] {
                                B_TOTAL_ASSIGNMENT_AGG[m][gap.Hours[t]] = sum[j in cfw.Tasks](B_TOTAL_ASSIGNMENT[m][j][gap.Hours[t]]);
                            }

                            max_free_periods = 0;
                            count_periods = 0;

                            for[t in gap.n_slots_arrival_job[job_conflicting]...HORIZON_EXTRA] {
                                if (!B_TOTAL_ASSIGNMENT_AGG[mec_chose][gap.Hours[t]]) {
                                    count_periods += 1;

                                    if (count_periods > max_free_periods) {
                                        max_free_periods = count_periods;
                                    }
                                } else {
                                    count_periods = 0;
                                }
                            }
                        }

                        println(" ");
                        println("ALOCANDO JOB PARA O NOVO MECANICO");
                        // Nao precisa remover do mecanico antigo porque foi usado o gap na restrição, nao foi alocado

                        found = false;

                        for[t in gap.n_slots_arrival_job[job_conflicting]...HORIZON_EXTRA : !found] {
                            if (!B_TOTAL_ASSIGNMENT_AGG[mec_chose][gap.Hours[t]]) {
                                local hability_count = 0;
                                for[t_ in t..(min(t + gap.t_time_processing_opt[job_conflicting] - 1, HORIZON_EXTRA-1))] {
                                    // println("Checando slot ", gap.Hours[t_], " para o job ", job_conflicting, " no mecanico ", mec_chose);
                                    if (!B_TOTAL_ASSIGNMENT_AGG[mec_chose][gap.Hours[t_]]) {
                                        hability_count += 1;
                                    }
                                    // println ("Slot ", gap.Hours[t_], " livre para o job ", job_conflicting, " no mecanico ", mec_chose);
                                }
                                // println("Mecanico ", mec_chose, " tem ", hability_count, " slots livres a partir do slot ", gap.Hours[t]);
                                if (hability_count == gap.t_time_processing_opt[job_conflicting]) {
                                    B_ASSIGNMENT_MEC_SCHED_OPT[mec_chose][job_conflicting][gap.Hours[t]] = true;
                                    println(job_conflicting, " DE TIPO ", cfw.k_task_type[job_conflicting], " ALOCADA COM SUCESSO PARA O ", mec_chose, " NO SLOT ", gap.Hours[t]);
                                    local end_job_conflicting = t + gap.t_time_processing_opt[job_conflicting] - 1;
                                    println("JOB ALOCADO: ", job_conflicting);
                                    println("Mecanico: ", mec_chose);
                                    println("Inicio: ", gap.Hours[t]);
                                    println("Fim: ", gap.Hours[end_job_conflicting]);
                                    println(" ");
                                    found = true;
                                }
                            }
                        }

                        if (!found) {
                            println("ERRO, NAO FOI POSSIVEL ALOCAR AO MECANICO");
                            return;
                        }

                    }

                    local horizon_extra = HORIZON_EXTRA;
                    
                    // Marcando e atualizando B_TOTAL_ASSIGNMENT novamente
                    for[m in cfw.Mechanics][j in cfw.Tasks][t in 0...horizon_extra] {
                        B_TOTAL_ASSIGNMENT[m][j][gap.Hours[t]] = false;
                    }
                    for[m in cfw.Mechanics][j in cfw.Tasks][t in 0...horizon_extra] {
                        if (B_ASSIGNMENT_MEC_SCHED_OPT[m][j][gap.Hours[t]]) {
                            local end_t = t + gap.t_time_processing_opt[j] - 1;

                            if (end_t >= horizon_extra) {
                                println("ERRO: job ultrapassa horizonte extra.");
                                println("Mecanico: ", m);
                                println("Job: ", j);
                                println("Inicio: ", gap.Hours[t]);
                                return;
                            }

                            for[t_ in t...(end_t + 1)] {
                                B_TOTAL_ASSIGNMENT[m][j][gap.Hours[t_]] = true;
                            }
                            // for[t_ in t...(t + gap.t_time_processing_opt[j])] {
                            //     B_TOTAL_ASSIGNMENT[m][j][gap.Hours[t_]] = true;
                            //     // println("Mecanico: ", m, " Job: ", j, " -> Slot: ", gap.Hours[t_], " com valor = ", B_ASSIGNMENT_MEC_SCHED_OPT[m][j][gap.Hours[t]]);
                            // }
                        }
                    }
                    for[m in cfw.Mechanics][t in 0...horizon_extra] {
                        B_TOTAL_ASSIGNMENT_AGG[m][gap.Hours[t]] = sum[j in cfw.Tasks](B_TOTAL_ASSIGNMENT[m][j][gap.Hours[t]]);
                    }

                    for[m in cfw.Mechanics][t in 0...horizon_extra] {
                        local occ = sum[j in cfw.Tasks](B_TOTAL_ASSIGNMENT[m][j][gap.Hours[t]]);

                        if (occ > 1) {
                            println("ERRO: SOBREPOSICAO DETECTADA");
                            println("Mecanico: ", m);
                            println("Slot: ", gap.Hours[t]);

                            for[j in cfw.Tasks : B_TOTAL_ASSIGNMENT[m][j][gap.Hours[t]]] {
                                println("Job sobreposto: ", j);
                            }

                            return;
                        }
                    }

                    B_ASSIGNMENT_OPT_HEURISTIC[mec_chose][job_conflicting] = true;

                    S_JOBS_MECHANIC[mec_chose] = {};
                    for[j in cfw.Tasks : B_ASSIGNMENT_OPT_HEURISTIC[mec_chose][j]] {
                        S_JOBS_MECHANIC[mec_chose].add(j);
                    }

                    GAP_ASSIGN_MEC_OPT[m_inf][job_conflicting] = 0;
                }

                println(" ");
                println("PARA MECANICO ALOCADO - EXECUTANDO HEURISTICA PARA ACHAR UPPER BOUND...");

                UB_SCHED_HEURISTIC[mec_chose] = computeHeuristicObj(mec_chose);

                println("LOWER BOUND DO ", mec_chose, ": ", LB_SCHED[mec_chose]);
                println("UPPER BOUND HEURISTICO ENCONTRADO PARA ", mec_chose, ": ", UB_SCHED_HEURISTIC[mec_chose]);

                local total_slack = sum[m in cfw.Mechanics][j in cfw.Tasks](GAP_ASSIGN_MEC_OPT[m][j]);
                if (total_slack == 0) {

                    local horizon_print = HORIZON_EXTRA;

                    for[m in cfw.Mechanics][j in S_JOBS_MECHANIC[m]][t in 0...horizon_print] {
                        if (B_ASSIGNMENT_MEC_SCHED_OPT[m][j][gap.Hours[t]]) {

                            local end_t_job = t + gap.t_time_processing_opt[j] - 1;

                            if (end_t_job < horizon_print) {

                                local status_gantt = "viabilizado";

                                if (t >= gap.n_mechanicslots || end_t_job >= gap.n_mechanicslots) {
                                    status_gantt = "hora_extra";
                                }

                                println(
                                    "GANTT;FINAL;",
                                    m, ";",
                                    j, ";",
                                    t, ";",
                                    end_t_job, ";",
                                    gap.Hours[t], ";",
                                    gap.Hours[end_t_job], ";",
                                    status_gantt
                                );
                            }
                        }
                    }

                    TOTAL_UB_HEURISTIC = sum[m in cfw.Mechanics](UB_SCHED_HEURISTIC[m]);

                    println(" ");
                    println("UPPER BOUND TOTAL AJUSTADO ", TOTAL_UB_HEURISTIC);
                    println("LOWER BOUND SCHEDULLING: ", TOTAL_LB);
                    println(" ");

                    println("GAP OTIMALIDADE: ", round(((TOTAL_UB_HEURISTIC - TOTAL_LB) / TOTAL_LB * 100) * 100) / 100, "%: ");
                    println(" ");

                } else {
                    println(" ");
                    println("PROXIMA ITERACAO...");
                    println(" ");
                }
            }
        }
    }
}