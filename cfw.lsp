function init() {

    Tasks = {};
    Tasks.add("Task 1");
    Tasks.add("Task 2");
    Tasks.add("Task 3");
    Tasks.add("Task 4");
    Tasks.add("Task 5");
    Tasks.add("Task 6");
    Tasks.add("Task 7");

    Mechanics = {};
    Mechanics.add("Mecanico 1");
    Mechanics.add("Mecanico 2");
    Mechanics.add("Mecanico 3");

    Specialitys = {};
    Specialitys.add("Motor");
    Specialitys.add("Revisao Rapida");
    Specialitys.add("Revisao");

    TaskTypes = {};
    TaskTypes.add("Cliente");
    TaskTypes.add("Interna");

    // Janela do dia: 09:00 ate 18:00
    t_input_start_unix = 1778673600.00;
    t_input_end_unix   = 1778706000.00;


    // =========================
    // Task 1 - Chegada 09:00
    // =========================
    t_processing_time["Task 1"] = 180;
    k_speciality_tasks["Task 1"] = "Revisao";
    t_hour_arrived_job_unix["Task 1"] = 1778673600.00;
    k_task_type["Task 1"] = "Cliente";


    // =========================
    // Task 2 - Chegada 09:30
    // =========================
    t_processing_time["Task 2"] = 150;
    k_speciality_tasks["Task 2"] = "Motor";
    t_hour_arrived_job_unix["Task 2"] = 1778675400.00;
    k_task_type["Task 2"] = "Cliente";


    // =========================
    // Task 3 - Chegada 10:20
    // =========================
    t_processing_time["Task 3"] = 130;
    k_speciality_tasks["Task 3"] = "Revisao Rapida";
    t_hour_arrived_job_unix["Task 3"] = 1778678400.00;
    k_task_type["Task 3"] = "Cliente";


    // =========================
    // Task 4 - Chegada 11:10
    // =========================
    t_processing_time["Task 4"] = 120;
    k_speciality_tasks["Task 4"] = "Revisao";
    t_hour_arrived_job_unix["Task 4"] = 1778681400.00;
    k_task_type["Task 4"] = "Interna";


    // =========================
    // Task 5 - Chegada 13:00
    // =========================
    t_processing_time["Task 5"] = 50;
    k_speciality_tasks["Task 5"] = "Motor";
    t_hour_arrived_job_unix["Task 5"] = 1778688000.00;
    k_task_type["Task 5"] = "Cliente";


    // =========================
    // Task 6 - Chegada 14:30
    // =========================
    t_processing_time["Task 6"] = 70;
    k_speciality_tasks["Task 6"] = "Revisao Rapida";
    t_hour_arrived_job_unix["Task 6"] = 1778693400.00;
    k_task_type["Task 6"] = "Cliente";


    // =========================
    // Task 7 - Chegada 16:00
    // =========================
    t_processing_time["Task 7"] = 65;
    k_speciality_tasks["Task 7"] = "Revisao";
    t_hour_arrived_job_unix["Task 7"] = 1778698800.00;
    k_task_type["Task 7"] = "Cliente";


    // =========================
    // Mecanicos
    // =========================

    b_avaliable_mechanic["Mecanico 1"] = true;
    k_speciality_mechanics["Mecanico 1"] = "Revisao";

    b_avaliable_mechanic["Mecanico 2"] = true;
    k_speciality_mechanics["Mecanico 2"] = "Motor";

    b_avaliable_mechanic["Mecanico 3"] = true;
    k_speciality_mechanics["Mecanico 3"] = "Revisao Rapida";
}