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

(* для HMI: 0=Выкл, 1=Рециркуляция, 2=Продувка, 3=Аспирация, 4=Прогрев клапанов *)
g_iModeDisp := g_iModeCoarse;
MOV(iState >= 200, 3, g_iModeDisp); (* Аспирация: 200 подготовка, 300 аспирация *)
MOV(iState = 210, 4, g_iModeDisp); (* Прогрев клапанов *)
MOV(iState >= 200 AND g_xManualAspActive, 5, g_iModeDisp); (* Асперация в ручном режиме *)

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
    g_xValveIn := FALSE; g_xValveOut := FALSE; g_xValveRecycle := FALSE;

    g_iPreheatLeft := 0; g_iAspLeft := 0; g_iRecircLeft := 0;
    g_xManualAspCmd := FALSE; (* сброс фронта ручной аспирации *)

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
        g_xValveIn := FALSE; g_xValveOut := FALSE; g_xValveRecycle := FALSE;
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
    IF AI_fTOutside <= F_FLT10(g_iToutHeat) THEN
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
    IF AI_fTOutside <= F_FLT10(g_iToutAsper) THEN
        g_xCmdHeat := FALSE;
        iState := STATE_RESET;
    END_IF;

210: (* ПОДОГРЕВ ЗАСЛОНОК *)
    INCP(M8014, g_iPreheatLeft);
    IF g_iPreheatLeft >= g_iPreheatTime THEN
        g_iPreheatLeft := 0; (* сброс счётчика подогрева *)

        (* Подогрев выключен *)
        g_xCmdHeat := FALSE;

        iState := STATE_ASPER; (* Аспирация *)
    END_IF;

300: (* АСПИРАЦИЯ: все 10 вент., приток/сброс открыты, рециркуляция закрыта *)
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
   ЧАСТЬ 1.5. ПРОГРЕСС И ОСТАВШЕЕСЯ ВРЕМЯ (для HMI)
   g_iProgress — 0..100 % выполнения текущей фазы (рециркуляция/прогрев/аспирация);
   g_iLeftTime — сколько минут осталось до конца текущей фазы.

   Длительности фаз:
   - рециркуляция: astIntens[g_iIntensity].RECIRC (мин);
   - прогрев: g_iPreheatTime, мин (счётчик g_iPreheatLeft);
   - аспирация: astIntens[g_iIntensity].ASPER (мин, регулярная) либо
                   g_iManualAspMin (ручная) — уже в локальном iAspTarget.

   Счётчики g_iRecircLeft / g_iPreheatLeft / g_iAspLeft считают ВВЕРХ
   (INCP по тику M8014, 1 мин), поэтому «осталось» = длительность − счётчик,
   «прогресс» = счётчик ÷ длительность × 100 %. В прочих состояниях
   (Выкл, Продувка, подготовка) — 0 % и 0 мин.
   ════════════════════════════════════════════════════════════════ *)
CASE iState OF
    100: (* РЕЦИРКУЛЯЦИЯ *)
        IF astIntens[g_iIntensity].RECIRC > 0 THEN
            g_iProgress := REAL_TO_INT(INT_TO_REAL(g_iRecircLeft) * 100.0
                                       / INT_TO_REAL(astIntens[g_iIntensity].RECIRC));
            g_iLeftTime := astIntens[g_iIntensity].RECIRC - g_iRecircLeft;
        ELSE
            g_iProgress := 0;
            g_iLeftTime := 0;
        END_IF;
    210: (* ПРОГРЕВ КЛАПАНОВ *)
        IF g_iPreheatTime > 0 THEN
            g_iProgress := REAL_TO_INT(INT_TO_REAL(g_iPreheatLeft) * 100.0
                                       / INT_TO_REAL(g_iPreheatTime));
            g_iLeftTime := g_iPreheatTime - g_iPreheatLeft;
        ELSE
            g_iProgress := 0;
            g_iLeftTime := 0;
        END_IF;
    300: (* АСПИРАЦИЯ *)
        IF iAspTarget > 0 THEN
            g_iProgress := REAL_TO_INT(INT_TO_REAL(g_iAspLeft) * 100.0
                                       / INT_TO_REAL(iAspTarget));
            g_iLeftTime := iAspTarget - g_iAspLeft;
        ELSE
            g_iProgress := 0;
            g_iLeftTime := 0;
        END_IF;
    ELSE
        g_iProgress := 0;
        g_iLeftTime := 0;
END_CASE;

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
   мгновенно). Выключение — сразу у всех; TOF держит выход ещё 3 с.

   РУЧНОЙ РЕЖИМ (Выключено, g_xModeManual = TRUE, iState = 2 = STATE_IDLE):
   каскад TON гасится (AND NOT g_xModeManual), а выход вентилятора берётся
   напрямую из команды g_xCmdFan* (M500–M509) БЕЗ TOF — мгновенное
   включение и выключение (см. SEL ниже).
   Условие (iState = STATE_IDLE) в ручной ветке защищает от гонки:
   в скане перехода Продувка/Авто -> Выключено iState уже 0
   (STATE_RESET), а не 2, поэтому ещё не сброшенные команды автомата
   (g_xCmdFan* = TRUE) НЕ проходят в ручную ветку и не включают
   вентиляторы все разом. *)
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


fbTOF1(IN := fbTON1.Q, PT := T#3s);
fbTOF2(IN := fbTON2.Q, PT := T#3s);
fbTOF3(IN := fbTON3.Q, PT := T#3s);
fbTOF4(IN := fbTON4.Q, PT := T#3s);
fbTOF5(IN := fbTON5.Q, PT := T#3s);
fbTOF6(IN := fbTON6.Q, PT := T#3s);
fbTOF7(IN := fbTON7.Q, PT := T#3s);
fbTOF8(IN := fbTON8.Q, PT := T#3s);
fbTOF9(IN := fbTON9.Q, PT := T#3s);
fbTOF10(IN := fbTON10.Q, PT := T#3s);

(* Выходы вентиляторов:
   - Авто/Продувка (g_xModeManual = FALSE): каскад TON + TOF 3 с;
   - Выключено, устойчивое (g_xModeManual = TRUE И iState = STATE_IDLE):
     ручная команда напрямую, БЕЗ TOF(мгновенное вкл/выкл);
   - переходный скан (g_xModeManual = TRUE, iState = 0): fbTOF*.Q —
     додержать каскадные, не включать новые (защита от гонки). *)
DO_FanH1 := SEL(g_xModeManual AND (iState = STATE_IDLE), fbTOF1.Q, g_xCmdFanH1);
DO_FanH2 := SEL(g_xModeManual AND (iState = STATE_IDLE), fbTOF2.Q, g_xCmdFanH2);
DO_FanH3 := SEL(g_xModeManual AND (iState = STATE_IDLE), fbTOF3.Q, g_xCmdFanH3);
DO_FanH4 := SEL(g_xModeManual AND (iState = STATE_IDLE), fbTOF4.Q, g_xCmdFanH4);
DO_FanH5 := SEL(g_xModeManual AND (iState = STATE_IDLE), fbTOF5.Q, g_xCmdFanH5);
DO_FanH6 := SEL(g_xModeManual AND (iState = STATE_IDLE), fbTOF6.Q, g_xCmdFanH6);
DO_FanR1 := SEL(g_xModeManual AND (iState = STATE_IDLE), fbTOF7.Q, g_xCmdFanR1);
DO_FanR2 := SEL(g_xModeManual AND (iState = STATE_IDLE), fbTOF8.Q, g_xCmdFanR2);
DO_FanR3 := SEL(g_xModeManual AND (iState = STATE_IDLE), fbTOF9.Q, g_xCmdFanR3);
DO_FanR4 := SEL(g_xModeManual AND (iState = STATE_IDLE), fbTOF10.Q, g_xCmdFanR4);

DO_FanH1 := DO_FanH1 AND NOT g_xAnyBlock AND g_iFun1State < 2;
DO_FanH2 := DO_FanH2 AND NOT g_xAnyBlock AND g_iFun2State < 2;
DO_FanH3 := DO_FanH3 AND NOT g_xAnyBlock AND g_iFun3State < 2;
DO_FanH4 := DO_FanH4 AND NOT g_xAnyBlock AND g_iFun4State < 2;
DO_FanH5 := DO_FanH5 AND NOT g_xAnyBlock AND g_iFun5State < 2;
DO_FanH6 := DO_FanH6 AND NOT g_xAnyBlock AND g_iFun6State < 2;

(* ── Клапаны (Belimo: питание = открыть, пружина = закрыть) ───── *)
fbTOF11(IN := g_xCmdValveIn1, PT := T#3s);
fbTOF12(IN := g_xCmdValveIn2, PT := T#3s);
fbTOF13(IN := g_xCmdValveOut1, PT := T#3s);
fbTOF14(IN := g_xCmdValveOut2, PT := T#3s);
fbTOF15(IN := g_xCmdValveRec1, PT := T#3s);
fbTOF16(IN := g_xCmdValveRec2, PT := T#3s);

DO_VlvIn1Open := SEL(g_xModeManual AND (iState = STATE_IDLE), fbTOF11.Q, g_xValveIn);
DO_VlvIn2Open := SEL(g_xModeManual AND (iState = STATE_IDLE), fbTOF12.Q, g_xValveIn);
DO_VlvOut1Open := SEL(g_xModeManual AND (iState = STATE_IDLE), fbTOF13.Q, g_xValveOut);
DO_VlvOut2Open := SEL(g_xModeManual AND (iState = STATE_IDLE), fbTOF14.Q, g_xValveOut);
DO_VlvRec1Open := SEL(g_xModeManual AND (iState = STATE_IDLE), fbTOF15.Q, g_xValveRecycle);
DO_VlvRec2Open := SEL(g_xModeManual AND (iState = STATE_IDLE), fbTOF16.Q, g_xValveRecycle);

(* ── Подогрев заслонок приток/сброс ──────────────────────────── *)
DO_HeatVlv := g_xCmdHeat;

(* ── Блокировка охладителя: 1 = запрет, 0 = разрешение ───────── *)
DO_CoolerStop := g_xCmdCoolerStop;
