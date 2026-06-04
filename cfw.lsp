use math;
use hexaly;
use io;

function init() {

    local instanceFile = "instancias/6_17.txt";

    readInstanceFromTxt(instanceFile);
}

function normalizeSpeciality(s) {

    if (s == "Revisao_Rapida") {
        return "Revisao Rapida";
    }

    return s;
}

function expectToken(f, expected) {

    local token = f.readString();

    if (token != expected) {
        throw "Erro ao ler arquivo. Esperado: " + expected + " | Encontrado: " + token;
    }
}

function readInstanceFromTxt(fileName) {

    local f = io.openRead(fileName);

    // =========================
    // Conjuntos
    // =========================

    Tasks = {};
    Mechanics = {};
    Specialitys = {};
    TaskTypes = {};

    Specialitys.add("Motor");
    Specialitys.add("Revisao Rapida");
    Specialitys.add("Revisao");

    TaskTypes.add("Cliente");
    TaskTypes.add("Interna");

    // =========================
    // ParÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢metros gerais
    // =========================

    expectToken(f, "START_UNIX");
    t_input_start_unix = f.readDouble();

    expectToken(f, "END_UNIX");
    t_input_end_unix = f.readDouble();

    // =========================
    // Tarefas
    // =========================

    expectToken(f, "N_TASKS");
    local nTasks = f.readInt();

    expectToken(f, "TASKS");

    for [i in 0...nTasks] {

        local task = f.readString();
        local processingTime = f.readDouble();
        local specialityRaw = f.readString();
        local arrivalUnix = f.readDouble();
        local taskType = f.readString();

        local speciality = normalizeSpeciality(specialityRaw);

        Tasks.add(task);

        t_processing_time[task] = processingTime;
        k_speciality_tasks[task] = speciality;
        t_hour_arrived_job_unix[task] = arrivalUnix;
        k_task_type[task] = taskType;

        Specialitys.add(speciality);
        TaskTypes.add(taskType);
    }

    // =========================
    // MecÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢nicos
    // =========================

    expectToken(f, "N_MECHANICS");
    local nMechanics = f.readInt();

    expectToken(f, "MECHANICS");

    for [i in 0...nMechanics] {

        local mechanic = f.readString();
        local available = f.readInt();
        local specialityRaw = f.readString();

        local speciality = normalizeSpeciality(specialityRaw);

        Mechanics.add(mechanic);

        b_avaliable_mechanic[mechanic] = available == 1;
        k_speciality_mechanics[mechanic] = speciality;

        Specialitys.add(speciality);
    }

    f.close();

    println("Instancia carregada: ", fileName);
    println("Numero de tarefas: ", nTasks);
    println("Numero de mecanicos: ", nMechanics);
}


