    use cfw;
    use math;
    use hexaly;
    use gap as gap;
    use schedulling as sh;
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

        TOTAL_TIME_SOLVER = 0;
        TIME_GAP_SOLVER = 0;
        TIME_SCHED_TOTAL_SOLVER = 0;
        TIME_SCHED_SOLVER[m in cfw.Mechanics] = 0;
        NB_SOLVES = 0;
    
        with (ls = hexaly.create()) {
            gap.run(ls);
            _solveStatus = gap._solveStatus;

            TIME_GAP_SOLVER = ls.statistics.runningTime;
            TOTAL_TIME_SOLVER += TIME_GAP_SOLVER;
            NB_SOLVES += 1;

            println(" ");
            println("TEMPO_SOLVER;GAP;", TIME_GAP_SOLVER, ";segundos");
            println(" ");
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


        B_ASSIGNMENT_MEC_SCHED_INITIAL[m in cfw.Mechanics][j in cfw.Tasks][h in gap.Hours] = false;
        GAP_ASSIGN_INITIAL[m in cfw.Mechanics][j in cfw.Tasks] = 0;

        for[m in cfw.Mechanics] {            
            with (ls = hexaly.create()) {
                sh.run(ls, m, S_JOBS_MECHANIC[m], LB_SCHED[m], UB_SCHED[m], warm_start, nil);
                _solveStatus = sh._solveStatus;
                STATUS_SCHED[m] = sh._solveStatus;

                TIME_SCHED_SOLVER[m] = ls.statistics.runningTime;
                TIME_SCHED_TOTAL_SOLVER += TIME_SCHED_SOLVER[m];
                TOTAL_TIME_SOLVER += TIME_SCHED_SOLVER[m];
                NB_SOLVES += 1;

                println(
                    "TEMPO_SOLVER;SCHED;",
                    m,
                    ";",
                    TIME_SCHED_SOLVER[m],
                    ";segundos"
                );

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

        contador = 0;

        if (m_inf == nil) {
            println("TODOS OS MECANICOS FICARAM VIAVEIS.");
            println(" ");
            println("LOWER BOUND SCHEDULLING: ", TOTAL_LB);
            println(" ");
        }
        else
        {
            while (sum[m in cfw.Mechanics][j in cfw.Tasks](GAP_ASSIGN_MEC_OPT[m][j]) > 0) {
                contador += 1;
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

                    if (contador == 1) {
                        // Só precisa calcular na primeira iteração, porque nas proximas ao fim se calcula
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
                    }


                    println(" ");
                    println("ENCONTRANDO MECANICO CANDIDATO A RECEBER O JOB...");

                    // achar o mecanico que pode pegar esse job
                    // 1. ter compatibilidade 2. ter slots disponiveis depois da data de chegada do job na quantidade necessária

                    // mantém n_mechanicslots normal porque verifica se tem mecanico candidato para receber o job no tempo normal
                    count_false[m in cfw.Mechanics] = 0;
                    for[m in cfw.Mechanics : m != m_inf][t in gap.n_slots_arrival_job[job_conflicting]...gap.n_mechanicslots : gap.b_compatible[m][job_conflicting]] {
                        // println("Checando mecanico ", m, " no slot ", gap.Hours[t], " para o job conflitante ", job_conflicting);
                        if (!B_TOTAL_ASSIGNMENT_AGG[m][gap.Hours[t]]) {
                            count_false[m] += 1;
                        }
                    }

                    mec_chose = nil;

                    // Primeiro: conta quantos mecânicos são candidatos
                    n_candidates = 0;
                    for[m in cfw.Mechanics] {
                        // println("Mecanico ", m, " tem ", count_false[m], " slots livres a partir do arrival do job conflitante.");
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
                            println("Mecanico ", m, " tem ", count_false_extra[m], " slots livres no horizonte extra.");
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

                        for[t in gap.n_slots_arrival_job[job_conflicting]...gap.n_mechanicslots] {
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
        
        println(" ");
        println("DECIDINDO HORARIO DE ALMOCO...");
        println(" ");

        local LUNCH_FIRST_SLOT = 18;        // 12:00
        local LUNCH_LAST_SLOT = 35;         // 14:50
        local LUNCH_DEFAULT_SLOT = 21;      // 12:30
        local LUNCH_DURATION_SLOTS = 6;     // 1h = 6 slots de 10 minutos
        local horizon_lunch = HORIZON_EXTRA;

        LUNCH_START_OPT[m in cfw.Mechanics] = nil;
        LUNCH_END_OPT[m in cfw.Mechanics] = nil;
        LUNCH_BREAK_JOB[m in cfw.Mechanics] = nil;

        LUNCH_JOB_PROCESSED[j in cfw.Tasks] = false;


        // ============================================================
        // 1. RECONSTRUIR OCUPACAO ANTES DE INSERIR ALMOCO
        // ============================================================

        for[m in cfw.Mechanics][j in cfw.Tasks][t in 0...horizon_lunch] {
            B_TOTAL_ASSIGNMENT[m][j][gap.Hours[t]] = false;
        }

        for[m in cfw.Mechanics][j in S_JOBS_MECHANIC[m]][t in 0...horizon_lunch] {

            if (B_ASSIGNMENT_MEC_SCHED_OPT[m][j][gap.Hours[t]]) {

                local end_t = t + gap.t_time_processing_opt[j] - 1;

                if (end_t >= horizon_lunch) {
                    println("ERRO: job ultrapassa horizonte extra antes do almoço.");
                    println("Mecanico: ", m);
                    println("Job: ", j);
                    println("Inicio: ", gap.Hours[t]);
                    return;
                }

                for[t_ in t...(end_t + 1)] {
                    B_TOTAL_ASSIGNMENT[m][j][gap.Hours[t_]] = true;
                }
            }
        }

        for[m in cfw.Mechanics][t in 0...horizon_lunch] {
            B_TOTAL_ASSIGNMENT_AGG[m][gap.Hours[t]] =
                sum[j in cfw.Tasks](B_TOTAL_ASSIGNMENT[m][j][gap.Hours[t]]);
        }


        // ============================================================
        // 2. DECIDIR E INSERIR ALMOCO PARA CADA MECANICO
        // ============================================================

        for[m in cfw.Mechanics] {

            local periodo_almoco = nil;
            local break_job = nil;

            println(" ");
            println("ANALISANDO ALMOCO DO ", m);


            // ========================================================
            // 2.1 PRIMEIRO SLOT LIVRE ENTRE 12:00 E 14:50
            // ========================================================

            for[t in LUNCH_FIRST_SLOT..LUNCH_LAST_SLOT : periodo_almoco == nil] {

                if (!B_TOTAL_ASSIGNMENT_AGG[m][gap.Hours[t]]) {

                    periodo_almoco = t;

                    println(
                        "Primeiro ponto disponivel encontrado para ",
                        m,
                        ": ",
                        gap.Hours[periodo_almoco]
                    );
                }
            }


            // ========================================================
            // 2.2 SE NAO EXISTIR SLOT LIVRE, PROCURAR FRONTEIRA ENTRE JOBS
            //     Um job termina em t - 1 e outro começa em t.
            // ========================================================

            if (periodo_almoco == nil) {

                println(
                    m,
                    " nao possui slot livre entre 12:00 e 14:50. Procurando fronteira entre jobs..."
                );

                for[t in LUNCH_FIRST_SLOT..LUNCH_LAST_SLOT : periodo_almoco == nil] {

                    local has_job_ending_before = false;
                    local has_job_starting_at = false;

                    for[j in S_JOBS_MECHANIC[m]] {

                        if (B_ASSIGNMENT_MEC_SCHED_OPT[m][j][gap.Hours[t]]) {
                            has_job_starting_at = true;
                        }

                        for[s in 0...horizon_lunch : !has_job_ending_before] {

                            if (B_ASSIGNMENT_MEC_SCHED_OPT[m][j][gap.Hours[s]]) {

                                local end_s = s + gap.t_time_processing_opt[j] - 1;

                                if (end_s + 1 == t) {
                                    has_job_ending_before = true;
                                }
                            }
                        }
                    }

                    if (has_job_ending_before && has_job_starting_at) {

                        periodo_almoco = t;

                        println(
                            "Fronteira entre jobs encontrada para ",
                            m,
                            " em ",
                            gap.Hours[periodo_almoco]
                        );
                    }
                }
            }


            // ========================================================
            // 2.3 SE NAO EXISTIR SLOT LIVRE NEM FRONTEIRA,
            //     QUEBRAR JOB NO HORARIO DEFAULT DE 12:30
            // ========================================================

            if (periodo_almoco == nil) {

                periodo_almoco = LUNCH_DEFAULT_SLOT;

                println(
                    m,
                    " nao possui slot livre nem fronteira entre jobs. Usando horario default: ",
                    gap.Hours[periodo_almoco]
                );

                for[j in S_JOBS_MECHANIC[m] : break_job == nil] {

                    for[s in 0...horizon_lunch : break_job == nil] {

                        if (B_ASSIGNMENT_MEC_SCHED_OPT[m][j][gap.Hours[s]]) {

                            local end_s = s + gap.t_time_processing_opt[j] - 1;

                            if (s < periodo_almoco && end_s >= periodo_almoco) {
                                break_job = j;
                            }
                        }
                    }
                }

                if (break_job != nil) {
                    println(
                        "Job que sera quebrado no meio pelo almoco: ",
                        break_job,
                        " do ",
                        m
                    );
                } else {
                    println(
                        "Nenhum job ativo no meio em ",
                        gap.Hours[periodo_almoco],
                        ". O almoco sera tratado como insercao normal."
                    );
                }
            }


            // ========================================================
            // 2.4 GRAVAR HORARIO DO ALMOCO
            // ========================================================

            LUNCH_START_OPT[m] = periodo_almoco;
            LUNCH_END_OPT[m] = periodo_almoco + LUNCH_DURATION_SLOTS;
            LUNCH_BREAK_JOB[m] = break_job;

            local lunch_start = LUNCH_START_OPT[m];
            local lunch_end = LUNCH_END_OPT[m];

            println(
                "Almoco definido para ",
                m,
                ": ",
                gap.Hours[lunch_start],
                " ate ",
                gap.Hours[lunch_end - 1]
            );


            // ========================================================
            // 2.5 DEFINIR PRIMEIRO SLOT LIVRE APOS O ALMOCO
            // ========================================================

            local current_free = lunch_end;

            if (break_job != nil) {

                local start_break = nil;
                local end_break = nil;

                for[s in 0...horizon_lunch : start_break == nil] {

                    if (B_ASSIGNMENT_MEC_SCHED_OPT[m][break_job][gap.Hours[s]]) {
                        start_break = s;
                        end_break = s + gap.t_time_processing_opt[break_job] - 1;
                    }
                }

                local remaining_slots = end_break - lunch_start + 1;

                current_free = lunch_end + remaining_slots;

                if (current_free >= horizon_lunch) {
                    println("ERRO: job quebrado pelo almoço ultrapassa horizonte extra.");
                    println("Mecanico: ", m);
                    println("Job: ", break_job);
                    return;
                }

                println(
                    break_job,
                    " sera interrompida em ",
                    gap.Hours[lunch_start],
                    " e retomada em ",
                    gap.Hours[lunch_end],
                    ". Agenda volta a ficar livre em ",
                    gap.Hours[current_free]
                );
            }


            // ========================================================
            // 2.6 EMPURRAR SOMENTE OS JOBS NECESSARIOS
            //     As lacunas futuras absorvem o deslocamento.
            // ========================================================

            for[j in cfw.Tasks] {
                LUNCH_JOB_PROCESSED[j] = false;
            }

            for[t in lunch_start...horizon_lunch] {

                for[j in S_JOBS_MECHANIC[m] : !LUNCH_JOB_PROCESSED[j]] {

                    if (j != break_job && B_ASSIGNMENT_MEC_SCHED_OPT[m][j][gap.Hours[t]]) {

                        LUNCH_JOB_PROCESSED[j] = true;

                        local old_start = t;
                        local dur_j = gap.t_time_processing_opt[j];
                        local old_end = old_start + dur_j - 1;

                        if (old_start < current_free) {

                            local new_start = current_free;
                            local new_end = new_start + dur_j - 1;

                            if (new_end >= horizon_lunch) {
                                println("ERRO: deslocamento do almoço joga job para fora do horizonte.");
                                println("Mecanico: ", m);
                                println("Job: ", j);
                                println("Inicio antigo: ", gap.Hours[old_start]);
                                println("Novo inicio idx: ", new_start);
                                return;
                            }

                            B_ASSIGNMENT_MEC_SCHED_OPT[m][j][gap.Hours[old_start]] = false;
                            B_ASSIGNMENT_MEC_SCHED_OPT[m][j][gap.Hours[new_start]] = true;

                            println(
                                j,
                                " do ",
                                m,
                                " empurrada de ",
                                gap.Hours[old_start],
                                " para ",
                                gap.Hours[new_start],
                                ". Deslocamento: ",
                                new_start - old_start,
                                " slots"
                            );

                            current_free = new_end + 1;

                        } else {

                            // Existe lacuna suficiente antes desse job.
                            // Logo, ele nao precisa ser empurrado.
                            current_free = old_end + 1;
                        }
                    }
                }
            }


            // ========================================================
            // 2.7 RECONSTRUIR OCUPACAO CONSIDERANDO O ALMOCO
            //     O job quebrado é tratado como duas partes.
            // ========================================================

            for[m_aux in cfw.Mechanics][j_aux in cfw.Tasks][t_aux in 0...horizon_lunch] {
                B_TOTAL_ASSIGNMENT[m_aux][j_aux][gap.Hours[t_aux]] = false;
            }

            for[m_aux in cfw.Mechanics][j_aux in S_JOBS_MECHANIC[m_aux]][t_aux in 0...horizon_lunch] {

                if (B_ASSIGNMENT_MEC_SCHED_OPT[m_aux][j_aux][gap.Hours[t_aux]]) {

                    local end_t_aux = t_aux + gap.t_time_processing_opt[j_aux] - 1;

                    if (end_t_aux >= horizon_lunch) {
                        println("ERRO: job ultrapassa horizonte extra apos almoço.");
                        println("Mecanico: ", m_aux);
                        println("Job: ", j_aux);
                        println("Inicio: ", gap.Hours[t_aux]);
                        return;
                    }

                    if (LUNCH_BREAK_JOB[m_aux] != nil && LUNCH_BREAK_JOB[m_aux] == j_aux) {

                        local lunch_start_aux = LUNCH_START_OPT[m_aux];
                        local lunch_end_aux = LUNCH_END_OPT[m_aux];

                        // Parte antes do almoço
                        if (t_aux < lunch_start_aux) {
                            for[t_part1 in t_aux...lunch_start_aux] {
                                B_TOTAL_ASSIGNMENT[m_aux][j_aux][gap.Hours[t_part1]] = true;
                            }
                        }

                        // Parte restante depois do almoço
                        local remaining_slots_aux = end_t_aux - lunch_start_aux + 1;
                        local restart_t_aux = lunch_end_aux;
                        local new_end_t_aux = restart_t_aux + remaining_slots_aux - 1;

                        if (new_end_t_aux >= horizon_lunch) {
                            println("ERRO: parte restante do job quebrado ultrapassa horizonte extra.");
                            println("Mecanico: ", m_aux);
                            println("Job: ", j_aux);
                            return;
                        }

                        for[t_part2 in restart_t_aux...(new_end_t_aux + 1)] {
                            B_TOTAL_ASSIGNMENT[m_aux][j_aux][gap.Hours[t_part2]] = true;
                        }

                    } else {

                        for[t_fill in t_aux...(end_t_aux + 1)] {
                            B_TOTAL_ASSIGNMENT[m_aux][j_aux][gap.Hours[t_fill]] = true;
                        }
                    }
                }
            }

            for[m_aux in cfw.Mechanics][t_aux in 0...horizon_lunch] {
                B_TOTAL_ASSIGNMENT_AGG[m_aux][gap.Hours[t_aux]] =
                    sum[j_aux in cfw.Tasks](B_TOTAL_ASSIGNMENT[m_aux][j_aux][gap.Hours[t_aux]]);
            }


            // ========================================================
            // 2.8 VALIDAR SE O HORARIO DE ALMOCO FICOU LIVRE
            // ========================================================

            for[t_lunch in LUNCH_START_OPT[m]...LUNCH_END_OPT[m]] {

                if (B_TOTAL_ASSIGNMENT_AGG[m][gap.Hours[t_lunch]]) {

                    println("ERRO: EXISTE JOB OCUPANDO HORARIO DE ALMOCO.");
                    println("Mecanico: ", m);
                    println("Slot: ", gap.Hours[t_lunch]);

                    for[j in cfw.Tasks : B_TOTAL_ASSIGNMENT[m][j][gap.Hours[t_lunch]]] {
                        println("Job no horario de almoco: ", j);
                    }

                    return;
                }
            }

            println(
                "Mecanico ",
                m,
                " almoca de ",
                gap.Hours[LUNCH_START_OPT[m]],
                " ate ",
                gap.Hours[LUNCH_END_OPT[m] - 1]
            );
        }


        // ============================================================
        // 3. VALIDAR SOBREPOSICAO FINAL ENTRE JOBS
        // ============================================================

        for[m in cfw.Mechanics][t in 0...horizon_lunch] {

            local occ = sum[j in cfw.Tasks](B_TOTAL_ASSIGNMENT[m][j][gap.Hours[t]]);

            if (occ > 1) {

                println("ERRO: SOBREPOSICAO DETECTADA APOS INSERCAO DO ALMOCO");
                println("Mecanico: ", m);
                println("Slot: ", gap.Hours[t]);

                for[j in cfw.Tasks : B_TOTAL_ASSIGNMENT[m][j][gap.Hours[t]]] {
                    println("Job sobreposto: ", j);
                }

                return;
            }
        }

        println(" ");
        println("ALMOCO INSERIDO COM SUCESSO PARA TODOS OS MECANICOS.");
        println(" ");


        // ============================================================
        // 4. IMPRIMIR GANTT FINAL COM ALMOCO
        //    Tipo novo: FINAL_LUNCH
        // ============================================================

        println("GANTT;tipo;mecanico;job;inicio_idx;fim_idx;inicio;fim;status");

        for[m in cfw.Mechanics] {

            // Linha do almoço
            println(
                "GANTT;FINAL_LUNCH;",
                m, ";",
                "Almoco;",
                LUNCH_START_OPT[m], ";",
                LUNCH_END_OPT[m] - 1, ";",
                gap.Hours[LUNCH_START_OPT[m]], ";",
                gap.Hours[LUNCH_END_OPT[m] - 1], ";",
                "almoco"
            );

            for[j in S_JOBS_MECHANIC[m]][t in 0...horizon_lunch] {

                if (B_ASSIGNMENT_MEC_SCHED_OPT[m][j][gap.Hours[t]]) {

                    local start_t = t;
                    local end_t = start_t + gap.t_time_processing_opt[j] - 1;

                    if (LUNCH_BREAK_JOB[m] != nil && LUNCH_BREAK_JOB[m] == j) {

                        local lunch_start = LUNCH_START_OPT[m];
                        local lunch_end = LUNCH_END_OPT[m];

                        // Parte 1 do job quebrado
                        if (start_t < lunch_start) {

                            println(
                                "GANTT;FINAL_LUNCH;",
                                m, ";",
                                j, "_parte_1;",
                                start_t, ";",
                                lunch_start - 1, ";",
                                gap.Hours[start_t], ";",
                                gap.Hours[lunch_start - 1], ";",
                                "quebrado_antes_almoco"
                            );
                        }

                        // Parte 2 do job quebrado
                        local remaining_slots = end_t - lunch_start + 1;
                        local restart_t = lunch_end;
                        local new_end_t = restart_t + remaining_slots - 1;

                        if (new_end_t >= horizon_lunch) {
                            println("ERRO: parte 2 do job quebrado ultrapassa horizonte.");
                            println("Mecanico: ", m);
                            println("Job: ", j);
                            return;
                        }

                        println(
                            "GANTT;FINAL_LUNCH;",
                            m, ";",
                            j, "_parte_2;",
                            restart_t, ";",
                            new_end_t, ";",
                            gap.Hours[restart_t], ";",
                            gap.Hours[new_end_t], ";",
                            "quebrado_depois_almoco"
                        );

                    } else {

                        local status_gantt = "viabilizado";

                        if (start_t >= gap.n_mechanicslots || end_t >= gap.n_mechanicslots) {
                            status_gantt = "hora_extra";
                        }

                        println(
                            "GANTT;FINAL_LUNCH;",
                            m, ";",
                            j, ";",
                            start_t, ";",
                            end_t, ";",
                            gap.Hours[start_t], ";",
                            gap.Hours[end_t], ";",
                            status_gantt
                        );
                    }
                }
            }
        }


        // ============================================================
        // 5. RECALCULAR UPPER BOUND APOS INSERCAO DO ALMOCO
        //    Usa o ultimo slot efetivamente ocupado por cada job.
        //    Isso corrige o caso em que um job foi partido no meio.
        // ============================================================

        println(" ");
        println("RECALCULANDO UPPER BOUND APOS INSERCAO DO ALMOCO...");
        println(" ");

        for[m in cfw.Mechanics] {

            local ub_m = 0;

            for[j in S_JOBS_MECHANIC[m]] {

                local first_slot_job = nil;
                local last_slot_job = nil;

                for[t in 0...horizon_lunch] {

                    if (B_TOTAL_ASSIGNMENT[m][j][gap.Hours[t]]) {

                        if (first_slot_job == nil) {
                            first_slot_job = t;
                        }

                        last_slot_job = t;
                    }
                }

                if (first_slot_job == nil || last_slot_job == nil) {

                    println("ATENCAO: job sem ocupacao efetiva no recálculo do UB.");
                    println("Mecanico: ", m);
                    println("Job: ", j);

                } else {

                    // last_slot_job é inclusivo.
                    // Portanto, o término efetivo é last_slot_job + 1.
                    local completion_effective = last_slot_job + 1;

                    local base_time = first_slot_job;

                    if (sh.b_type_task_client[j]) {
                        base_time = gap.n_slots_arrival_job[j];
                    }

                    local contribution = completion_effective - base_time;

                    ub_m += contribution;

                    if (LUNCH_BREAK_JOB[m] != nil && LUNCH_BREAK_JOB[m] == j) {

                        println(
                            "UB AJUSTADO - Job quebrado pelo almoco: ",
                            j,
                            " do ",
                            m,
                            " | inicio efetivo: ",
                            gap.Hours[first_slot_job],
                            " | termino efetivo: ",
                            gap.Hours[last_slot_job],
                            " | contribuicao: ",
                            contribution
                        );
                    }
                }
            }

            UB_SCHED_HEURISTIC[m] = ub_m;

            println(
                "UPPER BOUND RECALCULADO PARA ",
                m,
                ": ",
                UB_SCHED_HEURISTIC[m]
            );
        }


        // ============================================================
        // 6. RECALCULAR UB TOTAL E GAP FINAL COM ALMOCO
        // ============================================================

        TOTAL_UB_HEURISTIC = sum[m in cfw.Mechanics](UB_SCHED_HEURISTIC[m]);

        println(" ");
        println("UPPER BOUND TOTAL RECALCULADO COM ALMOCO: ", TOTAL_UB_HEURISTIC);
        println("LOWER BOUND SCHEDULLING: ", TOTAL_LB);

        if (TOTAL_LB > 0) {
            println(
                "GAP OTIMALIDADE COM ALMOCO: ",
                round(((TOTAL_UB_HEURISTIC - TOTAL_LB) / TOTAL_LB * 100) * 100) / 100,
                "%: "
            );
        }

        println(" ");
        println("========== TEMPO TOTAL DE EXECUCAO DO SOLVER ==========");
        println("Tempo GAP: ", TIME_GAP_SOLVER, " segundos");
        println("Tempo SCHED total: ", TIME_SCHED_TOTAL_SOLVER, " segundos");
        println("Numero de chamadas Hexaly: ", NB_SOLVES);
        println("Tempo total solver: ", TOTAL_TIME_SOLVER, " segundos");
        println("Tempo total solver: ", round((TOTAL_TIME_SOLVER / 60) * 100) / 100, " minutos");
        println("=======================================================");
        println(" ");

        println(" ");
        println("VERIFICANDO HORA EXTRA APOS 18:00...");
        println(" ");

        local OVERTIME_START_SLOT = gap.n_mechanicslots; // normalmente 54, equivalente a 18:00
        local total_overtime_slots = 0;
        local has_overtime = false;

        OVERTIME_JOB_SLOTS[m in cfw.Mechanics][j in cfw.Tasks] = 0;
        OVERTIME_MEC_SLOTS[m in cfw.Mechanics] = 0;

        // ============================================================
        // Conta slots ocupados a partir das 18:00
        // ============================================================

        for[m in cfw.Mechanics][j in S_JOBS_MECHANIC[m]][t in OVERTIME_START_SLOT...HORIZON_EXTRA] {

            if (B_TOTAL_ASSIGNMENT[m][j][gap.Hours[t]]) {

                OVERTIME_JOB_SLOTS[m][j] += 1;
                OVERTIME_MEC_SLOTS[m] += 1;
                total_overtime_slots += 1;
                has_overtime = true;
            }
        }

        // ============================================================
        // Print resumo
        // ============================================================

        if (!has_overtime) {

            println("HORA_EXTRA;NAO;0;minutos");
            println("Nao houve jobs executados depois das 18:00.");

        } else {

            local total_overtime_minutes = total_overtime_slots * 10;

            println("HORA_EXTRA;SIM;", total_overtime_minutes, ";minutos");
            println("Houve jobs executados depois das 18:00.");
            println("Tempo total de hora extra: ", total_overtime_minutes, " minutos");
            println(" ");

            println("HORA_EXTRA_DETALHE;mecanico;job;slots;minutos");

            for[m in cfw.Mechanics][j in S_JOBS_MECHANIC[m] : OVERTIME_JOB_SLOTS[m][j] > 0] {

                println(
                    "HORA_EXTRA_DETALHE;",
                    m, ";",
                    j, ";",
                    OVERTIME_JOB_SLOTS[m][j], ";",
                    OVERTIME_JOB_SLOTS[m][j] * 10
                );
            }

            println(" ");
            println("HORA_EXTRA_MECANICO;mecanico;slots;minutos");

            for[m in cfw.Mechanics : OVERTIME_MEC_SLOTS[m] > 0] {

                println(
                    "HORA_EXTRA_MECANICO;",
                    m, ";",
                    OVERTIME_MEC_SLOTS[m], ";",
                    OVERTIME_MEC_SLOTS[m] * 10
                );
            }
        }

        println(" ");
    }