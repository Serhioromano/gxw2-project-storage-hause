(*
  MAIN — главная программа (Program): БИЗНЕС-ЛОГИКА
  Проект: автоматизация камеры овощехранилища (ШУК.260726), ПЛК COOLMAY-L02
  Среда: GX Works 2, IEC 61131-3 Structured Text

  ФБ FB_PROCESS и FB_ACTUATORS УДАЛЕНЫ — их код вставлен в эту программу
  напрямую и объединён:
    1) конечный автомат режима «Авто» (рециркуляция / аспирация /
       ручная аспирация) + выбор грубого режима по переключателю;
    2) приводы: клапаны, вентиляторы, подогрев, блокировка охладителя Y00.

  Рутины (аналоговые входы, тревоги, световая колонна) вынесены в
  отдельную программу PRG_ROUTINE. Порядок выполнения программ в задаче:
  PRG_ROUTINE → PRG_MAIN (данные/тревоги до бизнес-логики).

  Программа INIT запускается отдельно, один раз при старте (см. PRG_INIT.st).
  HMI TK8100 читает входы/выходы и D/M-регистры напрямую — отдельного
  блока статусов HMI не требуется.

  Локальные переменные — в PRG_MAIN.csv.
 *)

(* Разрешение прерываний (EI) — первая строка каждой программы *)
EI(TRUE);

(* ════════════════════════════════════════════════════════════════
   ЧАСТЬ 1. КОНЕЧНЫЙ АВТОМАТ (код бывшего FB_PROCESS)
   ════════════════════════════════════════════════════════════════
   Состояния (g_iStep, D534 — для отладки/HMI):
      0 — СБРОС (однократный сброс выходов, безусловный переход в 2)
      2 — ОЖИДАНИЕ (Выключено; ожидание команды режима)
     50 — ПРОДУВКА (рециркуляция открыта, вентиляторы — вручную)
    100 — РЕЦИРКУЛЯЦИЯ (основное состояние)
    200 — ПОДГОТОВКА К АСПИРАЦИИ (проверка t улицы, решение: подогрев или сразу аспирация)
    210 — ПОДОГРЕВ ЗАСЛОНОК (греем ТЭН клапанов приток/сброс, потом открываем клапаны, включаем все вент., запускаем аспирацию)
    300 — АСПИРАЦИЯ (все 10 вент. уже включены в 210, только обратный отсчёт)

  Структура (по решению ревью): шаг 0 — только сброс, безусловно → 2;
  шаг 2 (ОЖИДАНИЕ) ждёт команду режима: Продувка → 50, Авто → 100,
  ручная аспирация → 200; при «Выключено» остаёмся в 2.
  Выход из «Авто» (100–300) при сигнале «не Авто» → шаг 0 → 2.

  Логика по плану §6.4:
  - рециркуляция: длительность по интенсивности (1200/600/300 мин),
    клапаны рециркуляции открыты, Y00 = 0; вентиляторы следуют за X03
    (охладитель) — реализовано ниже, в части «Приводы»;
  - перед аспирацией проверка t улицы: при t ≤ g_iToutAsper — пропуск
    цикла (слишком холодно); при t ≤ g_iToutHeat — подогрев заслонок;
  - аспирация 5 мин (300 с, регулярная) или g_iManualAspMin (ручная);
  - Y00 = 1 только во время аспирации (запрет охлаждения).

  Ручная аспирация (HMI: g_xManualAspCmd + g_iManualAspMin):
  - приоритет над регулярной; работает из любого режима;
  - по завершении возврат: в Авто — в рециркуляцию, иначе — в ОЖИДАНИЕ (2).

  Блокирующая тревога (g_xAnyBlock — реле фаз) НЕ останавливает автомат:
  блокируются только напорные вентиляторы (380 В). Разгонные (220 В)
  реле контроля фаз не затрагивает (ТЗ §7.6, v1.2).
 *)

(* Грубый выбор режима по переключателю
0 - Off
1 - Рециркуляция
2 - Продувка
 *)
g_iModeCoarse := SEL(DI_ModePurge, SEL(DI_ModeAuto, 0, 1), 2);

(* для HMI: 0=Выкл, 1=Рециркуляция, 2=Продувка, 3=Аспирация *)
g_iModeDisp := g_iModeCoarse;
MOV(iState >= 200, 3, g_iModeDisp); (* Аспирация *)

(* Если выключили во время аспирации *)
MOV(g_iModeCoarse = 0 AND iState >= 200, STATE_RESET, iState);

(* ── Фронт входа в состояние (однократные действия) ──────────── *)
xEntry := MEP(iState <> iPrevState);
iPrevState := iState;

(* Ручная аспирация из Выключено (возврат в этот же режим) *)
IF MEP(g_xManualAspCmd) THEN
    IF g_iModeDisp = 1 THEN
        g_xManualAspActive := TRUE;
        iState := STATE_PREPARE; (* подготовка к аспирации *)
    ELSE
        g_xManualAspCmd := FALSE; (* игнор команды, если уже в аспирации *)
        iState := STATE_PREPARE; (* подготовка к аспирации *)
    END_IF;
END_IF;

STATE_RESET := 0;
STATE_IDLE := 2;
STATE_PURGE := 50;
STATE_RECIRC := 100;
STATE_PREPARE := 200;
STATE_PREHEAT := 210;
STATE_ASPER := 300;

(* 0=низкая, 1=средняя, 2=высокая *)
g_iIntensity := LIMITATION(0, g_iIntensity, 2);

CASE iState OF
0: (* СБРОС: все выходы в безопасное состояние, безусловно → 2 *)
    (* Вентиляторы выключены, клапаны закрыты, подогрев выключен,
       холод не блокируется *)
    g_xCmdFanH1 := FALSE; g_xCmdFanH2 := FALSE;
    g_xCmdFanH3 := FALSE; g_xCmdFanH4 := FALSE;
    g_xCmdFanH5 := FALSE; g_xCmdFanH6 := FALSE;
    g_xCmdFanR1 := FALSE; g_xCmdFanR2 := FALSE;
    g_xCmdFanR3 := FALSE; g_xCmdFanR4 := FALSE;
    g_xCmdValveIn1 := FALSE; g_xCmdValveIn2 := FALSE;
    g_xCmdValveOut1 := FALSE; g_xCmdValveOut2 := FALSE;
    g_xCmdValveRec1 := FALSE; g_xCmdValveRec2 := FALSE;
    g_xCmdHeat := FALSE;
    g_xCmdCoolerStop := FALSE;
    g_xManualAspActive := FALSE;

    g_iPreheatLeft := 0; g_iAspLeft := 0; g_iRecircLeft := 0;

    iState := STATE_IDLE; (* безусловный переход в ОЖИДАНИЕ *)

2: (* ОЖИДАНИЕ Выключено: ждём команду режима *)
    (* Команды режима: Продувка → 50, Авто → 100 *)
    IF g_iModeCoarse = 1 THEN
        iState := STATE_RECIRC;
    ELSIF g_iModeCoarse = 2 THEN
        iState := STATE_PURGE;
    END_IF;

    IF iState <> STATE_IDLE THEN
        g_xCmdFanH1 := FALSE; g_xCmdFanH2 := FALSE;
        g_xCmdFanH3 := FALSE; g_xCmdFanH4 := FALSE;
        g_xCmdFanH5 := FALSE; g_xCmdFanH6 := FALSE;
        g_xCmdFanR1 := FALSE; g_xCmdFanR2 := FALSE;
        g_xCmdFanR3 := FALSE; g_xCmdFanR4 := FALSE;
        g_xCmdValveIn1 := FALSE; g_xCmdValveIn2 := FALSE;
        g_xCmdValveOut1 := FALSE; g_xCmdValveOut2 := FALSE;
        g_xCmdValveRec1 := FALSE; g_xCmdValveRec2 := FALSE;
        g_xCmdHeat := FALSE;
        g_xCmdCoolerStop := FALSE;
        g_xManualAspActive := FALSE;
    END_IF;

50: (* ПРОДУВКА: рециркуляция открыта, вентиляторы — вручную *)
    (* Команды режима: Выключено → через сброс в ОЖИДАНИЕ, Авто → 100 *)
    g_xCmdFanH1 := TRUE; g_xCmdFanH2 := TRUE;
    g_xCmdFanH3 := TRUE; g_xCmdFanH4 := TRUE;
    g_xCmdFanH5 := TRUE; g_xCmdFanH6 := TRUE;
    g_xCmdFanR1 := TRUE; g_xCmdFanR2 := TRUE;
    g_xCmdFanR3 := TRUE; g_xCmdFanR4 := TRUE;

    (* Клапаны: рециркуляция открыта, приток/сброс закрыты *)
    g_xCmdValveRec1 := TRUE; g_xCmdValveRec2 := TRUE;

    IF g_iModeCoarse <> 2 THEN
        iState := STATE_RESET;
    END_IF;

100: (* РЕЦИРКУЛЯЦИЯ *)
    g_xCmdFanH1 := DI_CoolerRun; g_xCmdFanH2 := DI_CoolerRun;
    g_xCmdFanH3 := DI_CoolerRun; g_xCmdFanH4 := DI_CoolerRun;
    g_xCmdFanH5 := DI_CoolerRun; g_xCmdFanH6 := DI_CoolerRun;
    g_xCmdFanR1 := DI_CoolerRun; g_xCmdFanR2 := DI_CoolerRun;
    g_xCmdFanR3 := DI_CoolerRun; g_xCmdFanR4 := DI_CoolerRun;

    (* Клапаны: рециркуляция открыта, приток/сброс закрыты *)
    g_xCmdValveRec1 := TRUE; g_xCmdValveRec2 := TRUE;

    IF g_iModeCoarse <> 1 THEN
        iState := STATE_RESET;
    END_IF;

    (* Тик 1 мин (M8014) — обратный отсчёт рециркуляции *)
    INCP(M8014, g_iRecircLeft);
    IF g_iRecircLeft >= astIntens[g_iIntensity].RECIRC THEN
        g_iRecircLeft := 0; (* сброс счётчика рециркуляции *)
        iState := STATE_PREPARE;
    END_IF;

200: (* ПОДГОТОВКА К АСПИРАЦИИ *)
    IF AI_fTOutside <= FLT10(g_iToutHeat) THEN
        g_xCmdHeat := TRUE;
        iState := STATE_PREHEAT; (* Подогрев *)
    ELSE
        iState := STATE_ASPER; (* Аспирация *)
    END_IF;

    IF g_xManualAspActive THEN
        iAspTarget := g_iManualAspMin; (* ручная аспирация: мин. время *)
    ELSE
        iAspTarget := astIntens[g_iIntensity].ASPER; (* регулярная аспирация: 5 мин *)
    END_IF;

    (* Если температура outside не превышает порог аспирации не будет иначе заморозим продукт *)
    IF AI_fTOutside <= FLT10(g_iToutAsper) THEN
        g_xCmdHeat := FALSE;
        iState := STATE_RESET;
    END_IF;

210: (* ПОДОГРЕВ ЗАСЛОНОК *)
    INCP(M8014, g_iPreheatLeft);
    IF g_iPreheatLeft >= g_iPreheatTime THEN
        g_iPreheatLeft := 0; (* сброс счётчика подогрева *)

        (* Подогрев выключен *)
        g_xCmdHeat := FALSE;

        (* Холод остановлен *)
        g_xCmdCoolerStop := TRUE;

        (* Вентиляторы: все 10 включены *)
        g_xCmdFanH1 := TRUE; g_xCmdFanH2 := TRUE;
        g_xCmdFanH3 := TRUE; g_xCmdFanH4 := TRUE;
        g_xCmdFanH5 := TRUE; g_xCmdFanH6 := TRUE;
        g_xCmdFanR1 := TRUE; g_xCmdFanR2 := TRUE;
        g_xCmdFanR3 := TRUE; g_xCmdFanR4 := TRUE;

        (* Клапаны: приток/сброс открыть, рециркуляцию закрыть *)
        g_xCmdValveIn1 := TRUE; g_xCmdValveIn2 := TRUE;
        g_xCmdValveOut1 := TRUE; g_xCmdValveOut2 := TRUE;
        g_xCmdValveRec1 := FALSE; g_xCmdValveRec2 := FALSE;

        iState := STATE_ASPER; (* Аспирация *)
    END_IF;

300: (* АСПИРАЦИЯ: все 10 вент., приток/сброс открыты, рециркуляция закрыта *)
    (* Выход из Авто → сброс *)
    IF g_iModeCoarse <> 1 THEN
        iState := STATE_RESET;
    END_IF;

    (* Обратный отсчёт аспирации *)
    INCP(M8014, g_iAspLeft);
    IF g_iAspLeft >= iAspTarget THEN
        g_iAspLeft := 0; (* сброс счётчика *)
        iState := STATE_RESET; (* завершение аспирации → сброс *)
    END_IF;

ELSE
    (* Неизвестное состояние — сброс в шаг 0 (СБРОС), страховка *)
    iState := 0;
END_CASE;

(* Номер состояния автомата — для отладки и HMI *)
g_iStep := iState;

(* ════════════════════════════════════════════════════════════════
   ЧАСТЬ 2. ПРИВОДЫ (код бывшего FB_ACTUATORS)
   ════════════════════════════════════════════════════════════════
   - напорные вентиляторы Y06–Y13 (6 шт.);
   - разгонные вентиляторы Y02–Y05 (4 шт., 220 В);
   - клапаны Belimo Y24–Y31 (питание = открыть, пружина = закрыть);
   - подогрев заслонок Y20–Y23 (4 ТЭН);
   - блокировка охладителя Y00 (1 = запрет охлаждения, 0 = разрешение).

   Особенности:
   - в режиме «Рециркуляция» (g_iModeDisp = 1) все вентиляторы следуют
     за охладителем X03 (ТЗ §7.3.1);
   - блокирующая тревога «реле фаз» (g_xAnyBlock) снимает команды
     ТОЛЬКО напорных вентиляторов (380 В); разгонные (220 В, 1-фазн.)
     РКФ не блокирует (ТЗ §7.6, v1.2);
   - в «Продувке» вентиляторами управляет оператор вручную — команды
     автомата в этом режиме равны FALSE (см. выше, состояние ПРОДУВКА).
 *)

(* ── Вентиляторы: каскадный пуск с интервалом 2 с ─────────────── *)
(* У каждого вентилятора СВОЙ таймер задержки включения (TON),
   отсчитываемый от фронта его собственной команды: FanH1 — 2 с,
   FanH2 — 4 с, ... FanR4 — 20 с. Так каскад работает одинаково и в
   Авто (все команды приходят разом), и в ручном режиме (вентиляторы
   включают по одному — каждый ждёт свою ступень, а не включается
   мгновенно). Выключение — сразу у всех; TOF держит выход ещё 3 с. *)
g_xModeManual := NOT DI_ModeAuto AND NOT DI_ModePurge; (* для HMI: ручной режим вентиляторов *)

fbTON1(IN := g_xCmdFanH1 AND NOT g_xModeManual, PT := T#2s);
fbTON2(IN := g_xCmdFanH2 AND NOT g_xModeManual, PT := T#4s);
fbTON3(IN := g_xCmdFanH3 AND NOT g_xModeManual, PT := T#6s);
fbTON4(IN := g_xCmdFanH4 AND NOT g_xModeManual, PT := T#8s);
fbTON5(IN := g_xCmdFanH5 AND NOT g_xModeManual, PT := T#10s);
fbTON6(IN := g_xCmdFanH6 AND NOT g_xModeManual, PT := T#12s);
fbTON7(IN := g_xCmdFanR1 AND NOT g_xModeManual, PT := T#14s);
fbTON8(IN := g_xCmdFanR2 AND NOT g_xModeManual, PT := T#16s);
fbTON9(IN := g_xCmdFanR3 AND NOT g_xModeManual, PT := T#18s);
fbTON10(IN := g_xCmdFanR4 AND NOT g_xModeManual, PT := T#20s);


fbTOF1(IN := fbTON1.Q OR (g_xCmdFanH1 AND g_xModeManual), PT := T#3s, Q := DO_FanH1);
fbTOF2(IN := fbTON2.Q OR (g_xCmdFanH2 AND g_xModeManual), PT := T#3s, Q := DO_FanH2);
fbTOF3(IN := fbTON3.Q OR (g_xCmdFanH3 AND g_xModeManual), PT := T#3s, Q := DO_FanH3);
fbTOF4(IN := fbTON4.Q OR (g_xCmdFanH4 AND g_xModeManual), PT := T#3s, Q := DO_FanH4);
fbTOF5(IN := fbTON5.Q OR (g_xCmdFanH5 AND g_xModeManual), PT := T#3s, Q := DO_FanH5);
fbTOF6(IN := fbTON6.Q OR (g_xCmdFanH6 AND g_xModeManual), PT := T#3s, Q := DO_FanH6);
fbTOF7(IN := fbTON7.Q OR (g_xCmdFanR1 AND g_xModeManual), PT := T#3s, Q := DO_FanR1);
fbTOF8(IN := fbTON8.Q OR (g_xCmdFanR2 AND g_xModeManual), PT := T#3s, Q := DO_FanR2);
fbTOF9(IN := fbTON9.Q OR (g_xCmdFanR3 AND g_xModeManual), PT := T#3s, Q := DO_FanR3);
fbTOF10(IN := fbTON10.Q OR (g_xCmdFanR4 AND g_xModeManual), PT := T#3s, Q := DO_FanR4);

DO_FanH1 := DO_FanH1 AND NOT g_xAnyBlock;
DO_FanH2 := DO_FanH2 AND NOT g_xAnyBlock;
DO_FanH3 := DO_FanH3 AND NOT g_xAnyBlock;
DO_FanH4 := DO_FanH4 AND NOT g_xAnyBlock;
DO_FanH5 := DO_FanH5 AND NOT g_xAnyBlock;
DO_FanH6 := DO_FanH6 AND NOT g_xAnyBlock;

(* ── Клапаны (Belimo: питание = открыть, пружина = закрыть) ───── *)
fbTOF11(IN := g_xCmdValveIn1, PT := T#3s, Q := DO_VlvIn1Open);
fbTOF12(IN := g_xCmdValveIn2, PT := T#3s, Q := DO_VlvIn2Open);
fbTOF13(IN := g_xCmdValveOut1, PT := T#3s, Q := DO_VlvOut1Open);
fbTOF14(IN := g_xCmdValveOut2, PT := T#3s, Q := DO_VlvOut2Open);
fbTOF15(IN := g_xCmdValveRec1, PT := T#3s, Q := DO_VlvRec1Open);
fbTOF16(IN := g_xCmdValveRec2, PT := T#3s, Q := DO_VlvRec2Open);

(* ── Подогрев заслонок приток/сброс ──────────────────────────── *)
DO_HeatVlv := g_xCmdHeat;

(* ── Блокировка охладителя: 1 = запрет, 0 = разрешение ───────── *)
DO_CoolerStop := g_xCmdCoolerStop;
