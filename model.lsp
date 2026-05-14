use cfw;
use math;
use hexaly;
use gap as gap;
use schedulling as sh;
use lunch as lch;

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

    for[j in S_JOBS_MECHANIC[m]][t in 0...gap.n_mechanicslots : B_ASSIGNMENT_MEC_SCHED_OPT[m][j][gap.Hours[t]]] {
        obj_value += 
            t 
            + gap.t_time_processing_opt[j] 
            - gap.n_slots_arrival_job[j];
    }

    return obj_value;
}

function main() {
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

    for[m in cfw.Mechanics][j in cfw.Tasks][t in 0...gap.n_mechanicslots] {
        B_ASSIGNMENT_MEC_SCHED_OPT[m][j][gap.Hours[t]] = false;
    }

    warm_start = false;
    contador = 0;

    while (contador < 1) {
        contador += 1;

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

            for[j in S_JOBS_MECHANIC[m]][t in 0...gap.n_mechanicslots] {
                B_ASSIGNMENT_MEC_SCHED_OPT[m][j][gap.Hours[t]] = sh.B_ASSIGNMENT_SCHED_OPT[j][gap.Hours[t]];
            }

            for[j in S_JOBS_MECHANIC[m]] {
                GAP_ASSIGN_MEC_OPT[m][j] = sh.GAP_ASSIGN_OPT[j];
            }

            if (_solveStatus == "INFEASIBLE" || _solveStatus == "INCONSISTENT") {
                println();
                println("NAO FOI POSSIVEL ENCONTRAR SOLUCAO VIAVEL");
                // return;
            }
        }

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
        }

        while (sum[m in cfw.Mechanics][j in cfw.Tasks](GAP_ASSIGN_MEC_OPT[m][j]) > 0) {

            for[m in cfw.Mechanics][j in S_JOBS_MECHANIC[m]: GAP_ASSIGN_MEC_OPT[m][j] == 1 && !found_infeasibility] {
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

                for[m in cfw.Mechanics][j in cfw.Tasks][t in 0...gap.n_mechanicslots] {
                    B_TOTAL_ASSIGNMENT[m][j][gap.Hours[t]] = false;
                }

                for[m in cfw.Mechanics][j in S_JOBS_MECHANIC[m]][t in 0...gap.n_mechanicslots] {
                    if (B_ASSIGNMENT_MEC_SCHED_OPT[m][j][gap.Hours[t]]) {
                        for[t_ in t...(t + gap.t_time_processing_opt[j])] {
                            B_TOTAL_ASSIGNMENT[m][j][gap.Hours[t_]] = true;
                        }
                    }
                }

                println(" ");
                println("ENCONTRANDO MECANICO CANDIDATO A RECEBER O JOB...");

                // achar o mecanico que pode pegar esse job
                // 1. ter compatibilidade 2. ter slots disponiveis depois da data de chegada do job na quantidade necessária

                count_false[m in cfw.Mechanics] = 0;
                for[m in cfw.Mechanics : m != m_inf][j in cfw.Tasks][t in gap.n_slots_arrival_job[job_conflicting]...gap.n_mechanicslots] {
                    // println("para a ", j, " laco de t -> ", gap.n_slots_arrival_job[j], " ate ", gap.n_mechanicslots);
                    if (!B_TOTAL_ASSIGNMENT[m][j][gap.Hours[t]]) {
                        count_false[m] += 1;
                        // println("somou no cont_false: ", m);
                    }
                }

                mec_chose = nil;
                found = false;
                for[m in cfw.Mechanics : !found] {
                    if (count_false[m] >= gap.t_time_processing_opt[job_conflicting]) {
                        mec_chose = m;
                        found = true;
                        println("MECANICO CANDIDATO ENCONTRADO: ", mec_chose);
                        println(" ");
                    }
                }

                iteracao = 0;
                max_free_periods = 0;

                while (max_free_periods < gap.t_time_processing_opt[job_conflicting]) {

                    iteracao += 1;

                    register_periods = {};
                    count_periods = 0;
                    // conta a qtd de períodos consecutivos livres no mecanico escolhido para ver se da pra colocar o job direto
                    for[j in cfw.Tasks][t in gap.n_slots_arrival_job[job_conflicting]...gap.n_mechanicslots] {
                        // println("para a ", j, " laco de t -> ", gap.n_slots_arrival_job[j], " ate ", gap.n_mechanicslots);
                        count_periods += 1;
                        register_periods.add(count_periods);
                        if (B_TOTAL_ASSIGNMENT[mec_chose][j][gap.Hours[t]]) {
                            count_periods = 0;
                            // println("somou no cont_false: ", m);
                        }
                    }

                    for[p in register_periods.values()] {
                        if (p > max_free_periods) {
                            max_free_periods = p;
                        }
                    }

                    // tratativa para empurrar os jobs alocados para frente e abrir espaço para o job_conflicting
                    if (max_free_periods < gap.t_time_processing_opt[job_conflicting]) {

                        found = false;
                        FREE_PERIODS[t in 0...gap.n_mechanicslots] = false;
                        // achando os primeiros slots vazios para empurrar os jobs alocados
                        for[j in cfw.Tasks][t in gap.n_slots_arrival_job[job_conflicting]...gap.n_mechanicslots] {
                            if (!B_TOTAL_ASSIGNMENT[mec_chose][j][gap.Hours[t]] && (FREE_PERIODS[t - 1] || !found)) {
                                FREE_PERIODS[t] = true;
                                found = true;
                            }
                        }

                        found = false;
                        FREE_PERIODS_OPT[t in 0...gap.n_mechanicslots] = false;
                        if (FREE_PERIODS[gap.n_slots_arrival_job[job_conflicting]]) {
                            // nao pode ser o primeiro, porque nao vai ter job pra mover, procurar os proximos
                            for[j in cfw.Tasks][t in gap.n_slots_arrival_job[job_conflicting]...gap.n_mechanicslots : !FREE_PERIODS[t]] {
                                if (!B_TOTAL_ASSIGNMENT[mec_chose][j][gap.Hours[t]] && (FREE_PERIODS_OPT[t - 1] || !found)) {
                                    FREE_PERIODS_OPT[t] = true;
                                    found = true;
                                }
                            }
                        } else {
                            for[t in gap.n_slots_arrival_job[job_conflicting]...gap.n_mechanicslots] {
                                FREE_PERIODS_OPT[t] = FREE_PERIODS[t];
                            }
                        }

                        count_free = sum[t in 0...gap.n_mechanicslots : FREE_PERIODS_OPT[t]](1);
                        // conta a qtd desses primeiros slots vazios

                        // empurrando os jobs alocados para frente
                        // olhar [t in gap.n_slots_arrival_job[job_conflicting]...gap.n_mechanicslots]
                        // nessa janela, até o último FREE_PERIODS_OPT[t], empurrar os jobs alocados para frente
                        // B_TOTAL_ASSIGNMENT <- marca os tempos em que o mecanico esta ocupado com os jobs
                        // B_ASSIGNMENT_MEC_SCHED_OPT <- marca o tempo em que o job iniciou com o mecanico

                        contador_jobs = 0;
                        achou_job = false;
                        for[j in cfw.Tasks][t in gap.n_slots_arrival_job[job_conflicting]...gap.n_mechanicslots] {
                            if (B_ASSIGNMENT_MEC_SCHED_OPT[mec_chose][j][gap.Hours[t]]) {
                                contador_jobs += 1;
                                // nao vai ser os primeiros, sempre vai ter um job antes dos count_free
                                // procuro entao, pelo segundo job a ser executado a partir desses periodos para o mecanico
                                if (contador_jobs == (iteracao + 1)) {
                                    achou_job = true;
                                    B_ASSIGNMENT_MEC_SCHED_OPT[mec_chose][j][gap.Hours[t]] = false;
                                    B_ASSIGNMENT_MEC_SCHED_OPT[mec_chose][j][gap.Hours[t + count_free]] = true;
                                }
                            }
                        }

                        FREE_PERIODS_END[t in 0...gap.n_mechanicslots] = false;
                        if (!achou_job) {
                            // tratar depois, quer dizer que nao tem mais job para empurrar
                            // no ultimo slot tem tempo livre, ver a qtd inversamente e empurrar todos os jobs a partir de t para frente
                            t_ini = gap.n_slots_arrival_job[job_conflicting];
                            t_fim = gap.n_mechanicslots;

                            found = false;
                            for[j in cfw.Tasks][k in 0...(t_fim - t_ini)] {
                                t = t_fim - 1 - k;
                                // contagem inversa para achar os ultimos slots vazios
                                if (!B_TOTAL_ASSIGNMENT[mec_chose][j][gap.Hours[t]] && (FREE_PERIODS_END[t - 1] || !found)) {
                                    FREE_PERIODS_END[t] = true;
                                    found = true;
                                }
                            }

                            // qtd de slots vazios que são a qtd que vou mover os jobs para frente
                            count_free_end = sum[t in 0...gap.n_mechanicslots : FREE_PERIODS_END[t]](1);

                            contador_jobs = 0;
                            achou_job = false;
                            for[j in cfw.Tasks][t in gap.n_slots_arrival_job[job_conflicting]...gap.n_mechanicslots] {
                                if (B_ASSIGNMENT_MEC_SCHED_OPT[mec_chose][j][gap.Hours[t]]) {

                                    B_ASSIGNMENT_MEC_SCHED_OPT[mec_chose][j][gap.Hours[t]] = false;
                                    B_ASSIGNMENT_MEC_SCHED_OPT[mec_chose][j][gap.Hours[t + count_free_end]] = true;
                                }
                            }
                        }

                        // Marcando e atualizando B_TOTAL_ASSIGNMENT novamente
                        for[m in cfw.Mechanics][j in cfw.Tasks][t in 0...gap.n_mechanicslots] {
                            B_TOTAL_ASSIGNMENT[m][j][gap.Hours[t]] = false;
                        }

                        for[m in cfw.Mechanics][j in S_JOBS_MECHANIC[m]][t in 0...gap.n_mechanicslots] {
                            if (B_ASSIGNMENT_MEC_SCHED_OPT[m][j][gap.Hours[t]]) {
                                for[t_ in t...(t + gap.t_time_processing_opt[j])] {
                                    B_TOTAL_ASSIGNMENT[m][j][gap.Hours[t_]] = true;
                                }
                            }
                        }
                    }
                    else
                    {
                        // caso normal ou ajustado empurrando os jobs, ja tem slots consecutivos livres
                        println(" ");
                        println("ALOCANDO JOB PARA O NOVO MECANICO");
                        // Nao precisa remover do mecanico antigo porque foi usado o gap na restrição, nao foi alocado

                        found = false;
                        for[j in cfw.Tasks][t in gap.n_slots_arrival_job[job_conflicting]...gap.n_mechanicslots : !found] {
                            if (!B_TOTAL_ASSIGNMENT[mec_chose][j][gap.Hours[t]]) {
                                B_ASSIGNMENT_MEC_SCHED_OPT[mec_chose][job_conflicting][gap.Hours[t]] = true;
                                println(job_conflicting, " ALOCADA COM SUCESSO PARA O ", mec_chose);
                                println(" ");
                                found = true;
                            }
                        }

                        B_ASSIGNMENT_OPT_HEURISTIC[mec_chose][job_conflicting] = true;

                        S_JOBS_MECHANIC[mec_chose] = {};
                        for[m in cfw.Mechanics][j in cfw.Tasks : B_ASSIGNMENT_OPT_HEURISTIC[m][j]] {
                            S_JOBS_MECHANIC[mec_chose].add(j);
                        }

                        GAP_ASSIGN_MEC_OPT[m_inf][job_conflicting] = 0;
                    }
                }

                println(" ");
                println("PARA MECANICO INVIAVEL - EXECUTANDO HEURISTICA PARA ACHAR UPPER BOUND...");

                UB_SCHED[m_inf] = computeHeuristicObj(m_inf);

                println("UPPER BOUND HEURISTICO ENCONTRADO PARA ", m_inf, ": ", UB_SCHED[m_inf]);
                println("LOWER BOUND SCHEDULLING: ", LB_SCHED[m_inf]);
                println(" ");

                println("GAP OTIMALIDADE: ", (UB_SCHED[m_inf] - LB_SCHED[m_inf]) / UB_SCHED[m_inf] * 100, "%: ");
                println(" ");

                WARM_START_SCHED[j in cfw.Tasks][h in gap.Hours] = 0;

                for[j in S_JOBS_MECHANIC[m_inf]][t in 0...gap.n_mechanicslots] {
                    WARM_START_SCHED[j][gap.Hours[t]] =
                        B_ASSIGNMENT_MEC_SCHED_OPT[m_inf][j][gap.Hours[t]];
                }

                println(" ");
                println("PARA MECANICO ALOCADO - EXECUTANDO HEURISTICA PARA ACHAR UPPER BOUND...");

                UB_SCHED[mec_chose] = computeHeuristicObj(mec_chose);

                println("UPPER BOUND HEURISTICO ENCONTRADO PARA ", mec_chose, ": ", UB_SCHED[mec_chose]);
                println("LOWER BOUND SCHEDULLING: ", LB_SCHED[mec_chose]);
                println(" ");

                println("GAP OTIMALIDADE: ", (UB_SCHED[mec_chose] - LB_SCHED[mec_chose]) / UB_SCHED[mec_chose] * 100, "%: ");
                println(" ");

                WARM_START_SCHED[j in cfw.Tasks][h in gap.Hours] = 0;
                warm_start = true;

                for[j in S_JOBS_MECHANIC[mec_chose]][t in 0...gap.n_mechanicslots] {
                    WARM_START_SCHED[j][gap.Hours[t]] =
                        B_ASSIGNMENT_MEC_SCHED_OPT[mec_chose][j][gap.Hours[t]];
                }
            }
        }
    }

}