(*
  FB_PROCESS — конечный автомат режима «Авто» (FB)
  Состояния (g_iStep, D534 — для отладки/HMI):
      0   — IDLE (Выключено / Продувка; автомат неактивен)
    100   — РЕЦИРКУЛЯЦИЯ (основное состояние)
    200   — ПОДГОТОВКА К АСПИРАЦИИ (Y00=1, клапаны, задержка пуска)
    300   — АСПИРАЦИЯ (все 10 вентиляторов, обратный отсчёт)
    400   — ЗАВЕРШЕНИЕ (закрыть приток/сброс, открыть рециркуляцию, Y00=0)

  Логика по плану §6.4:
  - рециркуляция: длительность по интенсивности (1200/600/300 мин),
    клапаны рециркуляции открыты, Y00 = 0; вентиляторы следуют за X20
    (охладитель) — реализовано в FB_ACTUATORS;
  - перед аспирацией проверка t улицы: g_iToutMin ≤ t ≤ g_iToutMax,
    иначе пропуск цикла; при t улицы < g_iTpreheat — подогрев заслонок;
  - пауза g_iStartDelay (30 с), затем аспирация 5 мин (300 с);
  - Y00 = 1 только во время аспирации (запрет охлаждения).

  Ручная аспирация (HMI: g_xManualAspCmd + g_iManualAspMin):
  - приоритет над регулярной; работает из любого режима;
  - по завершении возврат: в Авто — в рециркуляцию, иначе — в IDLE.

  Блокирующая тревога (g_xAnyBlock — реле фаз) останавливает автомат.

  Экземпляр ФБ: fbProcess (PRG_MAIN.csv). Локальные переменные — в FB_PROCESS.csv.
*)

(* Грубый выбор режима по переключателю *)
IF DI_ModePurge THEN
    g_iModeCoarse := 3;              (* Продувка — приоритет *)
ELSIF DI_ModeAuto THEN
    g_iModeCoarse := 1;              (* Авто *)
ELSE
    g_iModeCoarse := 0;              (* Выключено *)
END_IF;


(* ── Блокирующая тревога (реле фаз): останов автомата ─────────── *)
IF g_xAnyBlock THEN
    iState := 0;
    g_xManualAspActive := FALSE;
END_IF;

(* ── Смена режима не в «Авто» (без активной ручной аспирации) → IDLE *)
IF g_iModeCoarse <> 1 AND NOT g_xManualAspActive AND iState <> 0 THEN
    iState := 0;
END_IF;

(* ── Фронт входа в состояние (однократные действия) ──────────── *)
IF iState <> iPrevState THEN
    xEntry := TRUE;
    iPrevState := iState;
ELSE
    xEntry := FALSE;
END_IF;

CASE iState OF

0:  (* IDLE: Выключено / Продувка *)
    (* Вентиляторы ПЛК НЕ управляет (в Продувке — вручную оператором) *)
    g_xCmdFanH1 := FALSE; g_xCmdFanH2 := FALSE;
    g_xCmdFanH3 := FALSE; g_xCmdFanH4 := FALSE;
    g_xCmdFanH5 := FALSE; g_xCmdFanH6 := FALSE;
    g_xCmdFanR1 := FALSE; g_xCmdFanR2 := FALSE;
    g_xCmdFanR3 := FALSE; g_xCmdFanR4 := FALSE;

    (* Клапаны: Продувка — рециркуляция открыта; Выключено — все закрыты *)
    IF g_iModeCoarse = 3 THEN
        g_xCmdValveRec1 := TRUE;
        g_xCmdValveRec2 := TRUE;
    ELSE
        g_xCmdValveRec1 := FALSE;
        g_xCmdValveRec2 := FALSE;
    END_IF;
    g_xCmdValveIn1 := FALSE;  g_xCmdValveIn2 := FALSE;
    g_xCmdValveOut1 := FALSE; g_xCmdValveOut2 := FALSE;

    (* Подогрев выключен, холод не блокируется *)
    g_xCmdHeatIn1 := FALSE;  g_xCmdHeatIn2 := FALSE;
    g_xCmdHeatOut1 := FALSE; g_xCmdHeatOut2 := FALSE;
    g_xCmdCoolerStop := FALSE;

    g_iModeDisp := g_iModeCoarse;

    (* Вход в «Авто» *)
    IF g_iModeCoarse = 1 THEN
        iState := 100;
    END_IF;

    (* Ручная аспирация из Выключено/Продувки (возврат в этот же режим) *)
    IF MEP(g_xManualAspCmd) AND g_iModeCoarse <> 1 THEN
        g_xManualAspActive := TRUE;
        iAspTarget := g_iManualAspMin * 60;
        iState := 200;
    END_IF;

100: (* РЕЦИРКУЛЯЦИЯ *)
    IF xEntry THEN
        (* Длительность рециркуляции по интенсивности (план §6.4) *)
        CASE g_iIntensity OF
            0: g_iRecircLeft := 1200;   (* Слабо: 20 ч *)
            2: g_iRecircLeft := 300;    (* Интенсивно: 5 ч *)
            ELSE
               g_iRecircLeft := 600;    (* Нормально: 10 ч *)
        END_CASE;
    END_IF;

    (* Клапаны: рециркуляция открыта, приток/сброс закрыты *)
    g_xCmdValveIn1 := FALSE;  g_xCmdValveIn2 := FALSE;
    g_xCmdValveOut1 := FALSE; g_xCmdValveOut2 := FALSE;
    g_xCmdValveRec1 := TRUE;  g_xCmdValveRec2 := TRUE;

    (* Холод разрешён; подогрев выключен *)
    g_xCmdCoolerStop := FALSE;
    g_xCmdHeatIn1 := FALSE;  g_xCmdHeatIn2 := FALSE;
    g_xCmdHeatOut1 := FALSE; g_xCmdHeatOut2 := FALSE;
    (* Вентиляторы в рециркуляции следуют за X20 — см. FB_ACTUATORS *)

    (* Ручная аспирация прерывает цикл *)
    IF MEP(g_xManualAspCmd) THEN
        g_xManualAspActive := TRUE;
        iAspTarget := g_iManualAspMin * 60;
        iState := 200;
    END_IF;

    (* Тик 1 мин (M8014) — обратный отсчёт рециркуляции *)
    IF MEP(M8014) THEN
        g_iRecircLeft := g_iRecircLeft - 1;
        IF g_iRecircLeft <= 0 THEN
            iAspTarget := 300;          (* регулярная аспирация 5 мин *)
            iState := 200;
        END_IF;
    END_IF;

    g_iModeDisp := 1;

200: (* ПОДГОТОВКА К АСПИРАЦИИ *)
    IF xEntry THEN
        xAspEntry := TRUE;
    END_IF;

    IF xAspEntry THEN
        xAspEntry := FALSE;
        (* Проверка t улицы — только для регулярной аспирации *)
        IF (NOT g_xManualAspActive) AND
           (AI_TOutside < g_iToutMin OR AI_TOutside > g_iToutMax) THEN
            iState := 100;              (* пропуск цикла *)
            xSkip := TRUE;
        ELSE
            xSkip := FALSE;
            iFinishLeft := g_iStartDelay;  (* задержка пуска вентиляторов *)
            IF AI_TOutside < g_iTpreheat THEN
                iPreheatLeft := g_iPreheatTime;
            ELSE
                iPreheatLeft := 0;
            END_IF;
        END_IF;
    END_IF;

    IF NOT xSkip THEN
        (* Холод остановлен *)
        g_xCmdCoolerStop := TRUE;
        (* Клапаны: приток/сброс открыть, рециркуляцию закрыть *)
        g_xCmdValveIn1 := TRUE;  g_xCmdValveIn2 := TRUE;
        g_xCmdValveOut1 := TRUE; g_xCmdValveOut2 := TRUE;
        g_xCmdValveRec1 := FALSE; g_xCmdValveRec2 := FALSE;
        (* Подогрев заслонок (при t улицы ниже порога) *)
        g_xCmdHeatIn1 := (iPreheatLeft > 0);
        g_xCmdHeatIn2 := (iPreheatLeft > 0);
        g_xCmdHeatOut1 := (iPreheatLeft > 0);
        g_xCmdHeatOut2 := (iPreheatLeft > 0);
        (* Вентиляторы выключены (задержка пуска) *)
        g_xCmdFanH1 := FALSE; g_xCmdFanH2 := FALSE;
        g_xCmdFanH3 := FALSE; g_xCmdFanH4 := FALSE;
        g_xCmdFanH5 := FALSE; g_xCmdFanH6 := FALSE;
        g_xCmdFanR1 := FALSE; g_xCmdFanR2 := FALSE;
        g_xCmdFanR3 := FALSE; g_xCmdFanR4 := FALSE;

        (* Тик 1 с (M8013) *)
        IF MEP(M8013) THEN
            IF iPreheatLeft > 0 THEN
                iPreheatLeft := iPreheatLeft - 1;
            END_IF;
            iFinishLeft := iFinishLeft - 1;
            IF iFinishLeft <= 0 THEN
                iState := 300;
            END_IF;
        END_IF;
    END_IF;

    g_iModeDisp := 2;

300: (* АСПИРАЦИЯ *)
    IF xEntry THEN
        g_iAspLeft := iAspTarget;
    END_IF;

    (* Холод остановлен; клапаны приток/сброс открыты *)
    g_xCmdCoolerStop := TRUE;
    g_xCmdValveIn1 := TRUE;  g_xCmdValveIn2 := TRUE;
    g_xCmdValveOut1 := TRUE; g_xCmdValveOut2 := TRUE;
    g_xCmdValveRec1 := FALSE; g_xCmdValveRec2 := FALSE;
    (* Подогрев продолжается до истечения таймера *)
    g_xCmdHeatIn1 := (iPreheatLeft > 0);
    g_xCmdHeatIn2 := (iPreheatLeft > 0);
    g_xCmdHeatOut1 := (iPreheatLeft > 0);
    g_xCmdHeatOut2 := (iPreheatLeft > 0);
    (* Все 10 вентиляторов включены (независимо от X20) *)
    g_xCmdFanH1 := TRUE; g_xCmdFanH2 := TRUE;
    g_xCmdFanH3 := TRUE; g_xCmdFanH4 := TRUE;
    g_xCmdFanH5 := TRUE; g_xCmdFanH6 := TRUE;
    g_xCmdFanR1 := TRUE; g_xCmdFanR2 := TRUE;
    g_xCmdFanR3 := TRUE; g_xCmdFanR4 := TRUE;

    (* Тик 1 с (M8013) — обратный отсчёт аспирации *)
    IF MEP(M8013) THEN
        IF iPreheatLeft > 0 THEN
            iPreheatLeft := iPreheatLeft - 1;
        END_IF;
        g_iAspLeft := g_iAspLeft - 1;
        IF g_iAspLeft <= 0 THEN
            iState := 400;
        END_IF;
    END_IF;

    g_iModeDisp := 2;

400: (* ЗАВЕРШЕНИЕ АСПИРАЦИИ *)
    IF xEntry THEN
        iFinishLeft := 3;   (* пауза на закрытие клапанов *)
    END_IF;

    (* Возврат к рециркуляции: холод разрешён, рециркуляция открыта *)
    g_xCmdCoolerStop := FALSE;
    g_xCmdValveIn1 := FALSE;  g_xCmdValveIn2 := FALSE;
    g_xCmdValveOut1 := FALSE; g_xCmdValveOut2 := FALSE;
    g_xCmdValveRec1 := TRUE;  g_xCmdValveRec2 := TRUE;
    g_xCmdHeatIn1 := FALSE;  g_xCmdHeatIn2 := FALSE;
    g_xCmdHeatOut1 := FALSE; g_xCmdHeatOut2 := FALSE;
    (* Вентиляторы выключены *)
    g_xCmdFanH1 := FALSE; g_xCmdFanH2 := FALSE;
    g_xCmdFanH3 := FALSE; g_xCmdFanH4 := FALSE;
    g_xCmdFanH5 := FALSE; g_xCmdFanH6 := FALSE;
    g_xCmdFanR1 := FALSE; g_xCmdFanR2 := FALSE;
    g_xCmdFanR3 := FALSE; g_xCmdFanR4 := FALSE;

    (* Тик 1 с (M8013) *)
    IF MEP(M8013) THEN
        iFinishLeft := iFinishLeft - 1;
        IF iFinishLeft <= 0 THEN
            g_xManualAspActive := FALSE;
            IF g_iModeCoarse = 1 THEN
                iState := 100;          (* возврат в рециркуляцию *)
            ELSE
                iState := 0;            (* возврат в предыдущий режим *)
            END_IF;
        END_IF;
    END_IF;

    g_iModeDisp := 2;

ELSE
    (* Неизвестное состояние — сброс в IDLE (страховка) *)
    iState := 0;

END_CASE;

(* Номер состояния автомата — для отладки и HMI *)
g_iStep := iState;
