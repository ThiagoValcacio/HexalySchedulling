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

    model();

    println(" ");
    println("================= INICIANDO LUNCH ==================");
    println(" ");
    println(" ");

    minimize 0;

    ls.model.close();

    solve(ls);
    postSolve();

    if (ls.solution.status == "INCONSISTENT") {
        iis = ls.computeInconsistency();
        println(iis);
    }

}

function model() {

    
}

function postSolve() {
    
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
    if (feasible && (time - _timeToFeasible) > 1000) ls.stop();

}

function isFeasible() {
    return _solveStatus == "OPTIMAL" || _solveStatus == "FEASIBLE";
}