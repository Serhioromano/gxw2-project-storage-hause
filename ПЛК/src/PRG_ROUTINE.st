(*
  PRG_ROUTINE — программа рутин (Program)
  Проект: автоматизация камеры овощехранилища (ШУК.260726), ПЛК COOLMAY-L02
  Среда: GX Works 2, IEC 61131-3 Structured Text

  Содержит «рутины» — вспомогательные слои, не являющиеся бизнес-логикой:
    1) слой аналоговых входов (код бывшего FB_IO): масштабирование
       7 каналов, коррекции, обрывы; выходы блоков масштабирования (INT, ×10)
       через функцию FLT10 → глобальные REAL-переменные AI_f* (для HMI-графиков);
    2) тревоги AlarmManager V203 (код бывшего FB_ALARMS): AM_SET ×28,
       сводные флаги, упаковка для HMI, сброс/автосброс;
    3) световая колонна: вызов ФБ FB_LIGHT (единственный оставшийся ФБ);
    4) Modbus slave (порт 2, RS-485): инициализация для диспетчеризации/PUSH
       (xInit = M8002 или кнопка «Сброс тревог» HMI) — адрес 1, 9600 8N1
       (план §7, задел активирован).

  ФБ FB_IO и FB_ALARMS УДАЛЕНЫ — их код вставлен в эту программу напрямую.
  Бизнес-логика (автомат + приводы) — в программе PRG_MAIN.
  Порядок выполнения программ в задаче: PRG_ROUTINE → PRG_MAIN
  (данные/тревоги до бизнес-логики).

  Тикер TCO_TICKER_50 (TimeControl V2) здесь НЕ вызывается — он настроен
  и работает в отдельной программе TimeControl (план §2).

  Локальные переменные — в PRG_ROUTINE.csv.
*)

(* Разрешение прерываний (EI) — первая строка каждой программы *)
EI(TRUE);

(* ════════════════════════════════════════════════════════════════
   ЧАСТЬ 1. СЛОЙ АНАЛОГОВЫХ ВХОДОВ (код бывшего FB_IO)
   ════════════════════════════════════════════════════════════════
   - host AI0:  температура улицы, датчик 0-10 В (D8030), диапазон
                −50…+50 °C → °C×10, обрыв — по ErrWire (тревога 23);
   - host AI2:  температура в камере, ПВТ110 4-20 мА (D8032),
                диапазон −40…+80 °C → °C×10;
   - host AI3:  влажность в камере, ПВТ110 4-20 мА (D8033),
                диапазон 5…95 % → %×10;
   - модуль L02-RTD: щупы продукта 1–4 (R23700–R23703) — готовые °C×10;
   - средняя температура продукта по 4 щупам.

   МАСШТАБИРОВАННЫЕ ЗНАЧЕНИЯ: SCALE_AI/L02_SCALE_AI выдают INT в масштабе
   ×10 (например, 245 = 24.5 °C). Для HMI-графиков/трендов TK8100 значения
   переводятся функцией FLT10 в REAL (числовое значение сохраняется, ×10;
   деление на 10 — на панели) и пишутся в глобальные REAL-метки AI_f*
   (IO.csv: D0–D15, по 2 слова на REAL). Логика (тревоги, автомат) читает
   те же AI_f* — сравнивает с порогами в масштабе ×10 как и раньше.

   Коррекция датчиков (настройки HMI, °C×10):
   - g_iCorrTout — датчик улицы;
   - g_iCorrTprod1..4 — щупы продукта 1–4.
   Значение Correction прибавляется к результату (см. Utils V3).

   ОБРЫВЫ host-датчиков определяются по ErrWire SCALE_AI и регистрируются
   (fbAMSet 23–25) СРАЗУ после каждого вызова масштабирования ниже.
   Масштабированные значения пишутся в метки AI_f* (REAL, D0–D15),
   которые читают остальные блоки и HMI.

   Именование: AI_f* — REAL (float), AI_i* — INT (сырые значения).

   Один экземпляр SCALE_AI используется для всех host-каналов,
   один экземпляр L02_SCALE_AI — для всех щупов (см. Utils V3).
*)

(* Host AI0: температура улицы, датчик 0-10 В (−50…+50 °C → −500…+500 °C×10).
   Экземпляр fbScaleHost общий для 3 каналов — ErrWire и ValueOut читаем
   СРАЗУ после вызова (следующий вызов их перезапишет).
   Значение SCALE_AI (INT, ×10) через FLT10 → глобальная REAL (для HMI). *)
fbScaleHost(AINum := 0, SType := STYPE_0_10V, Min := -500, Max := 500,
            Correction := g_iCorrTout, FilterTime := 10, FilterNum := 100);
fbAMSet(iNum := 23, xState := fbScaleHost.ErrWire);  (* обрыв 0-10 В *)
AI_fTOutside := FLT10(fbScaleHost.ValueOut);

(* Host AI2: температура в камере (ПВТ110, 4-20 мА, −40…+80 °C) *)
fbScaleHost(AINum := 2, SType := STYPE_4_20MA, Min := -400, Max := 800);
fbAMSet(iNum := 24, xState := fbScaleHost.ErrWire);  (* обрыв 4-20 мА, t камеры *)
AI_fTChamber := FLT10(fbScaleHost.ValueOut);

(* Host AI3: влажность в камере (ПВТ110, 4-20 мА, 5…95 %) *)
fbScaleHost(AINum := 3, SType := STYPE_4_20MA, Min := 50, Max := 950);
fbAMSet(iNum := 25, xState := fbScaleHost.ErrWire);  (* обрыв 4-20 мА, влажность *)
AI_fHChamber := FLT10(fbScaleHost.ValueOut);

(* L02-RTD: щупы температуры продукта 1–4 (готовые °C×10,
   контроль обрыва модулем не выполняется — детекция по значению).
   Экземпляр fbScaleRtd общий для 4 щупов — ValueOut читаем сразу. *)
fbScaleRtd(AINum := 0, SType := STYPE_PT100, Correction := g_iCorrTprod1);
AI_fTProd1 := FLT10(fbScaleRtd.ValueOut);
fbScaleRtd(AINum := 1, SType := STYPE_PT100, Correction := g_iCorrTprod2);
AI_fTProd2 := FLT10(fbScaleRtd.ValueOut);
fbScaleRtd(AINum := 2, SType := STYPE_PT100, Correction := g_iCorrTprod3);
AI_fTProd3 := FLT10(fbScaleRtd.ValueOut);
fbScaleRtd(AINum := 3, SType := STYPE_PT100, Correction := g_iCorrTprod4);
AI_fTProd4 := FLT10(fbScaleRtd.ValueOut);

(* Средняя температура продукта (для HMI, D14; REAL — точнее, чем INT) *)
AI_fTProdAvg := (AI_fTProd1 + AI_fTProd2 + AI_fTProd3 + AI_fTProd4) / 4.0;

(* ════════════════════════════════════════════════════════════════
   ЧАСТЬ 2. ТРЕВОГИ ALARMMANAGER V203 (код бывшего FB_ALARMS)
   ════════════════════════════════════════════════════════════════
   - регистрация условий 28 тревог (AM_SET) — нумерация 0–27, план §5;
   - сводные флаги: g_xAnyAlarm (AM_HAS_ALARM), g_xAnyBlock (AM_IS_BLOCK);
   - упаковка тревог для HMI: D550 (биты 0–15), D551 (биты 16–27);
   - сброс: ручной (кнопка HMI g_xAlarmResetHmi) и автосброс
     (g_xAutoReset = TRUE, через g_iAutoResetDelay минут).

   Полярности входов (проверить при пусконаладке, см. вопросы):
   - концевики клапанов — контакт НЗ: «открыт» = вход 0, «не открыт» = вход 1;
   - РД-ДД200 — контакт НЗ: «поток есть» = вход 0, «нет потока» = вход 1.

   Обрывы host-датчиков (23–25) регистрируются по fbScaleHost.ErrWire
   СРАЗУ после масштабирования в части 1 и здесь НЕ повторяются.
   Обрыв щупов Pt100 (19–22) — по значению ≤ −1900 (модуль L02-RTD
   контроля обрыва не имеет, см. план §4, п.5).
*)

(* ── Регистрация условий тревог ───────────────────────────────── *)
(* 0: реле контроля фаз — ошибка фазировки *)
fbAMSet(iNum := 0, xState := DI_PhaseFault);

(* 1–6: клапан не открылся (команда «открыть» есть, концевик не сработал) *)
fbAMSet(iNum := 1, xState := DO_VlvIn1Open AND DI_VlvIn1Open);
fbAMSet(iNum := 2, xState := DO_VlvIn2Open AND DI_VlvIn2Open);
fbAMSet(iNum := 3, xState := DO_VlvOut1Open AND DI_VlvOut1Open);
fbAMSet(iNum := 4, xState := DO_VlvOut2Open AND DI_VlvOut2Open);
fbAMSet(iNum := 5, xState := DO_VlvRec1Open AND DI_VlvRec1Open);
fbAMSet(iNum := 6, xState := DO_VlvRec2Open AND DI_VlvRec2Open);

(* 7–12: нет потока воздуха, напорные вентиляторы 1–6 *)
fbAMSet(iNum := 7,  xState := DO_FanH1 AND DI_Flow1);
fbAMSet(iNum := 8,  xState := DO_FanH2 AND DI_Flow2);
fbAMSet(iNum := 9,  xState := DO_FanH3 AND DI_Flow3);
fbAMSet(iNum := 10, xState := DO_FanH4 AND DI_Flow4);
fbAMSet(iNum := 11, xState := DO_FanH5 AND DI_Flow5);
fbAMSet(iNum := 12, xState := DO_FanH6 AND DI_Flow6);

(* 13–18: пускатель напорного вентилятора не замкнулся (ОС не пришла) *)
fbAMSet(iNum := 13, xState := DO_FanH1 AND NOT DI_FanHFb1);
fbAMSet(iNum := 14, xState := DO_FanH2 AND NOT DI_FanHFb2);
fbAMSet(iNum := 15, xState := DO_FanH3 AND NOT DI_FanHFb3);
fbAMSet(iNum := 16, xState := DO_FanH4 AND NOT DI_FanHFb4);
fbAMSet(iNum := 17, xState := DO_FanH5 AND NOT DI_FanHFb5);
fbAMSet(iNum := 18, xState := DO_FanH6 AND NOT DI_FanHFb6);

(* 19–22: обрыв Pt100 — щупы продукта 1–4 (значение ≤ −190 °C) *)
fbAMSet(iNum := 19, xState := AI_fTProd1 <= -1900);
fbAMSet(iNum := 20, xState := AI_fTProd2 <= -1900);
fbAMSet(iNum := 21, xState := AI_fTProd3 <= -1900);
fbAMSet(iNum := 22, xState := AI_fTProd4 <= -1900);

(* 26: температура продукта выше максимума (любой из 4 щупов) *)
fbAMSet(iNum := 26, xState := (AI_fTProd1 > g_iTprodMax) OR
                              (AI_fTProd2 > g_iTprodMax) OR
                              (AI_fTProd3 > g_iTprodMax) OR
                              (AI_fTProd4 > g_iTprodMax));

(* 27: влажность ниже минимума (исключая обрыв 4-20 мА) *)
fbAMSet(iNum := 27, xState := (AI_fHChamber < g_iHmin) AND
                              (AI_iRawHChamber < 32720));

(* ── Сводные флаги для логики и HMI ──────────────────────────── *)
fbAMHas(iProcessNum := 0, iSeverity := 0, Q := g_xAnyAlarm, AC := g_iAlarmCount);
fbAMBlock(iProcessNum := 0, iSeverity := 0, Q := g_xAnyBlock);

(* ── Упаковка тревог для HMI: D550 (0–15), D551 (16–27) ──────── *)
fbAMPack(DNUM := 550, PD := AM_PACK_D);

(* ── Сброс тревог ────────────────────────────────────────────── *)
(* Ручной сброс — кнопка HMI (фронт M523) *)
xResetCmd := MEP(g_xAlarmResetHmi);

(* Автосброс: включён (g_xAutoReset = TRUE), тревоги активны —
   по истечении g_iAutoResetDelay минут выполняется AM_RESET.
   Ограничение HMI: g_iAutoResetDelay ≤ 500 мин (INT, счёт в секундах). *)
IF MEP(g_xAnyAlarm AND g_xAutoReset) THEN
    xResetArmed := TRUE;
    iAutoResetCount := g_iAutoResetDelay * 60;
END_IF;
IF NOT g_xAnyAlarm THEN
    xResetArmed := FALSE;
END_IF;
IF xResetArmed AND MEP(M8013) THEN
    IF iAutoResetCount > 0 THEN
        iAutoResetCount := iAutoResetCount - 1;
    END_IF;
END_IF;
IF xResetArmed AND iAutoResetCount <= 0 THEN
    xResetCmd := TRUE;
    xResetArmed := FALSE;
END_IF;

(* AM_RESET удерживает сигнал сброса 1 с (см. AlarmManager V203) *)
fbAMReset(IN := xResetCmd);

(* ════════════════════════════════════════════════════════════════
   ЧАСТЬ 3. СВЕТОВАЯ КОЛОННА (ФБ FB_LIGHT)
   ════════════════════════════════════════════════════════════════
   Выбор режима и индикация по плану §6.7. FB_LIGHT — единственный
   оставшийся в проекте функциональный блок (кроме библиотечных).
*)
fbLight();

(* ════════════════════════════════════════════════════════════════
   ЧАСТЬ 4. MODBUS SLAVE — ПОРТ 2 (RS-485) ════════════════════════
   Инициализация слейва для диспетчеризации / PUSH-интеграции:
   внешний мастер (шлюз/облако) опрашивает ПЛК по Modbus RTU.
   - порт 2 (клеммник RS-485), адрес slave = 1, 9600 8N1;
   - xInit (вход функции MB_SLAVE_INIT_PORT2): M8002 (первый скан ПЛК)
     ИЛИ кнопка HMI «Сброс тревог» (g_xAlarmResetHmi). По Modbus.EN.md
     слейв (пере)инициализируется по КАЖДОМУ фронту xInit, поэтому
     оборачивать вызов в IF M8002 НЕ нужно — условие передаётся во вход;
   - адресация регистров слейва — по умолчанию библиотеки (прямой доступ
     к D-регистрам ПЛК); буфер D600–D800 (план §7) нужен только для режима
     Master (MB_PROCESS_50), если он понадобится позже;
   - PortSettings — параметры порта (DWORD, возврат MB_PORT_SETTINGS);
   - xMbDummy — фиктивный приёмник результата функции: по Modbus.EN.md
     вызов функции-выражения как оператора требует присваивания слева.

   ⚠ Полярность: для включения Modbus slave порт 2 ПЛК должен быть
   настроен на RS-485 (аппаратно), адрес/скорость — выше.
*)
PortSettings := MB_PORT_SETTINGS(MB_PARITY_NONE, MB_STOPBIT_1, MB_BPS_9600);
xMbDummy := MB_SLAVE_INIT_PORT2(M8002 OR g_xAlarmResetHmi, 1, PortSettings);
