use cfw;
use math;

function solve(ls) {
    _nbLogs = 0;
    _timeToFeasible = nil;

    ls.solve();
    _solveStatus = ls.solution.status;
    logFunction(ls, nil);
}

function formatHour(seconds_day) {
    seconds_day = mod(seconds_day, 24 * 60 * 60);

    h = floor(seconds_day / 3600);
    m = floor(mod(seconds_day, 3600) / 60);

    h_str = h < 10 ? "0" + h : "" + h;
    m_str = m < 10 ? "0" + m : "" + m;

    return h_str + ":" + m_str;
}

function run(ls) {
    ls.addCallback("TIME_TICKED", logFunction);
    ls.addCallback("TIME_TICKED", stoppingCriterion);
    ls.param.verbosity = 0;

    for[m in cfw.Mechanics][j in cfw.Tasks] {
        b_compatible[m][j] = false;
    }

    for[m in cfw.Mechanics][j in cfw.Tasks] {
        local esp_task = cfw.k_speciality_tasks[j];
        local esp_mec = cfw.k_speciality_mechanics[m];
        b_compatible[m][j] = false;
        if (esp_mec == "Motor") {
            b_compatible[m][j] = true;
        } else if (esp_mec == "Revisao") {
            if (esp_task != "Motor") {
                b_compatible[m][j] = true;
            }
        } else if (esp_mec == "Revisao Rapida") {
            if (esp_task == "Revisao Rapida") {
                b_compatible[m][j] = true;
            }
        }
    }

    n_seconds_day = 24 * 60 * 60;
    n_seconds_slot = 10 * 60;
    n_timezone_offset_seconds = -3 * 60 * 60;

    t_start_unix_int = floor(cfw.t_input_start_unix);
    t_end_unix_int = floor(cfw.t_input_end_unix);

    t_start_day_seconds = mod(t_start_unix_int + n_timezone_offset_seconds + n_seconds_day, n_seconds_day);
    t_end_day_seconds = mod(t_end_unix_int + n_timezone_offset_seconds + n_seconds_day, n_seconds_day);

    n_duration_seconds = t_end_day_seconds - t_start_day_seconds;
    n_total_slots = floor(n_duration_seconds / n_seconds_slot);

    Hours[t in 0...n_total_slots] = formatHour(t_start_day_seconds + t * n_seconds_slot);
    n_mechanicslots = n_total_slots;
    n_mechanicslots_gap = n_total_slots - 6;

    for[m in cfw.Mechanics][t in 0...n_total_slots] {
        local aux = (t <= n_mechanicslots) ? n_mechanicslots - t : 0;
        n_slots_disp_mec[m][t] = aux;
    }

    for[j in cfw.Tasks] {
        t_time_processing_opt[j] = ceil(cfw.t_processing_time[j] / 10);
        local t_arrived_job_unix_int = floor(cfw.t_hour_arrived_job_unix[j]);
        local t_arrived_job_seconds = mod(t_arrived_job_unix_int + n_timezone_offset_seconds + n_seconds_day, n_seconds_day);
        local t_arrival_since_start = (t_start_day_seconds < t_arrived_job_seconds) ? t_arrived_job_seconds - t_start_day_seconds : 0;
        n_slots_arrival_job[j] = floor(t_arrival_since_start / n_seconds_slot);
    }

    for[j in cfw.Tasks][t in 0...n_total_slots] {
        b_can_execute[j][t] = (n_slots_arrival_job[j] <= t ) ? true : false;
    }

    model();

    println(" ");
    println("================= INICIANDO GAP ==================");
    println(" ");
    println(" ");

    // obj <- sum[j in cfw.Tasks][m in cfw.Mechanics : b_compatible[m][j]](t_time_processing_opt[j] * B_ASSIGNMENT[m][j] + 
    //     ((cfw.k_speciality_tasks[j] != cfw.k_speciality_mechanics[m]) ? 1 : 0) * t_time_processing_opt[j] * B_ASSIGNMENT[m][j]);

    obj <- sum[j in cfw.Tasks][m in cfw.Mechanics : b_compatible[m][j]](t_time_processing_opt[j] * B_ASSIGNMENT[m][j]);

    minimize obj;

    ls.model.close();

    solve(ls);
    postSolve();

    if (ls.solution.status == "INCONSISTENT") {
        iis = ls.computeInconsistency();
        println(iis);
    }

}

function model() {

    for[m in cfw.Mechanics][j in cfw.Tasks] {
        B_ASSIGNMENT[m][j] <- bool();
    }

    for[m in cfw.Mechanics] {
        local st_capacity <- sum[j in cfw.Tasks : b_compatible[m][j]](t_time_processing_opt[j] * B_ASSIGNMENT[m][j]) <= n_mechanicslots_gap;
        st_capacity.name = "Restricao de capacidade -- Mecanico: " + m + " <= " + n_mechanicslots_gap;
        constraint st_capacity;
    }

    for[j in cfw.Tasks] {
        local st_mandatory_assign <- sum[m in cfw.Mechanics : b_compatible[m][j]](B_ASSIGNMENT[m][j]) == 1;
        st_mandatory_assign.name = "Atribuicao obrigatoria -- Task: " + j;
        constraint st_mandatory_assign;
    }
}

function postSolve() {
    for[j in cfw.Tasks][m in cfw.Mechanics] {
        if (B_ASSIGNMENT[m][j].value) {
            println("Mecanico: ", m, " Task: ", j, " -> ", B_ASSIGNMENT[m][j].value);
        }
        B_ASSIGNMENT_OPT[m][j] = B_ASSIGNMENT[m][j].value;
    }
}

function logFunction(ls, cbTypes) {
    local stats = ls.statistics;
    local time = stats.runningTime;
    local sol = ls.solution;
    local valid = (sol.status == "FEASIBLE" || sol.status == "OPTIMAL");

    local nbObjs = ls.model.objectives.count();
    local objs[i in 0...nbObjs] = ls.model.objectives[i].value;

    if (_nbLogs % 50 == 0) {
        print("Time    ");
        for[i in 0...nbObjs-1] {
            print("Viol-",i+1,"    [Gap %]   ");
        }
        println("Obj       [Gap %]");
    }
    local str_time = ""+time;
    while(str_time.length() < 8) str_time = str_time + " ";

    local str_objs = "";
    for[i in 0...nbObjs] {
        local obj = (valid) ? math.round(ls.model.objectives[i].value*1e4) * 1e-4 : "Inf";
        local str_obj = ""+obj;
        while( str_obj.length() < 10) str_obj = str_obj + " ";
        str_objs = str_objs + str_obj;

        local obj_gap = (valid) ?  math.round(sol.objectiveGaps[i] * 1e4)*1e-2+ "%" : "Inf";
        local str_obj_gap = "["+obj_gap+"]";
        while(str_obj_gap.length() < 10) str_obj_gap = str_obj_gap + " ";
        str_objs = str_objs + str_obj_gap;
    }

    println(str_time,str_objs);
    _nbLogs += 1;
}

function stoppingCriterion(ls, cbTypes) {    
    local stats = ls.statistics;
    local time = stats.runningTime;
    local sol = ls.solution;
    local feasible = (sol.status == "FEASIBLE" || sol.status == "OPTIMAL");

    local nbObjs = ls.model.objectives.count();
    local gaps[i in 0...nbObjs] = math.round(ls.solution.objectiveGaps[i] * 1e4) * 1e-2;
    local objs[i in 0...nbObjs] = ls.model.objectives[i].value;

    // Looking for feasibility;
    if (!feasible && time > 1000) ls.stop();

    // Register the time that the solution became feasible
    if (feasible && _timeToFeasible == nil) _timeToFeasible = time;

    // Minimizing OF
    if (feasible && (time - _timeToFeasible) > opt_optimizationTimeLimit) ls.stop();

}

function isFeasible() {
    return _solveStatus == "OPTIMAL" || _solveStatus == "FEASIBLE";
}