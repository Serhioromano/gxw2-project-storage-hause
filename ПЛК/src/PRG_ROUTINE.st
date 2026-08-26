(*
  PRG_ROUTINE — программа рутин (Program)
  Проект: автоматизация камеры овощехранилища (ШУК.260726), ПЛК COOLMAY-L02
  Среда: GX Works 2, IEC 61131-3 Structured Text

  Содержит «рутины» — вспомогательные слои, не являющиеся бизнес-логикой:
    1) слой аналоговых входов (код бывшего FB_IO): масштабирование
       7 каналов, коррекции, обрывы; выходы блоков масштабирования (INT, ×10)
       через функцию FLT10 → глобальные REAL-переменные AI_f* (для HMI-графиков);
    2) тревоги AlarmManager V212 (код бывшего FB_ALARMS): FB_AM_SET ×34,
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
   - host AI0: температура улицы, датчик 0-10 В (D8030), диапазон
                −50…+50 °C → °C×10, обрыв — по ErrWire (тревога 23);
   - host AI2: температура в камере, ПВТ110 4-20 мА (D8032),
                диапазон −40…+80 °C → °C×10;
   - host AI3: влажность в камере, ПВТ110 4-20 мА (D8033),
                диапазон 5…95 % → %×10;
   - модуль L02-RTD: щупы продукта 1–4 (R23700–R23703) — готовые °C×10;
   - средняя температура продукта по 4 щупам.

   МАСШТАБИРОВАННЫЕ ЗНАЧЕНИЯ: SCALE_AI/L02_SCALE_AI выдают INT в масштабе
   ×10 (например, 245 = 24.5 °C). Для HMI-графиков/трендов TK8100 значения
   переводятся функцией FLT10 в REAL (числовое значение сохраняется, ×10;
   деление на 10 — на панели) и пишутся в глобальные REAL-метки AI_f*
   (IO.csv: D0–D15, по 2 слова на REAL).

   СРАВНЕНИЯ В ЛОГИКЕ (тип!):
   - host-каналы (t улицы, t/влажность в камере) — тревоги и автомат читают
     AI_f* (REAL, НАТУРАЛЬНЫЕ единицы: FLT10 делит на 10), пороги-настройки
     (g_iToutMin/Max, g_iTpreheat, g_iHmin — INT в масштабе ×10)
     преобразуются функцией FLT10: в GX Works 2 IEC ST нет неявного
     преобразования REAL↔INT в операциях сравнения, а INT_TO_REAL без
     деления оставил бы порог в ×10 (неверно);
   - щупы продукта (L02-RTD) — модуль уже выдаёт ГОТОВУЮ температуру °C×10
     в R23700…R23703 (INT), поэтому тревоги 19–22 и 26 сравнивают эти
     регистры напрямую с порогами (INT ↔ INT), без перевода в REAL.

   Коррекция датчиков (настройки HMI, °C×10):
   - g_iCorrTout — датчик улицы;
   - g_iCorrTprod1..4 — щупы продукта 1–4.
   Значение Correction прибавляется к результату (см. Utils V3).
   ВНИМАНИЕ: коррекция щупов применяется в AI_fTProd* (для HMI), но не
   в тревогах 19–22/26 (там — сырые R23700…R23703). Если нужна коррекция
   и в тревогах — сравнивать AI_fTProd* с FLT10(порог).

   ОБРЫВЫ host-датчиков определяются по ErrWire SCALE_AI и регистрируются
   (fbAMSet 23–25) СРАЗУ после каждого вызова масштабирования ниже.
   Масштабированные значения пишутся в метки AI_f* (REAL, D0–D15),
   которые читают остальные блоки и HMI.

   Именование: AI_f* — REAL (float), AI_i* — INT(сырые значения).

   Один экземпляр SCALE_AI используется для всех host-каналов,
   один экземпляр L02_SCALE_AI — для всех щупов (см. Utils V3).
 *)


g_xCoolerWorks := DI_CoolerRun;
g_xIsAuto := DI_ModeAuto;

(* Host AI0: температура улицы, датчик 0-10 В (−50…+50 °C → −500…+500 °C×10).
   Экземпляр fbScaleHost общий для 3 каналов — ErrWire и ValueOut читаем
   СРАЗУ после вызова (следующий вызов их перезапишет).
   Значение SCALE_AI (INT, ×10) через FLT10 → глобальная REAL (для HMI). *)
fbScaleHost(AINum := 0, SType := STYPE_0_10V, Min := -500, Max := 500,
            Correction := g_iCorrTout, FilterTime := 10, FilterNum := 100);
fbAMSet(iNum := 23, xState := fbScaleHost.ErrWire); (* обрыв 0-10 В *)
AI_fTOutside := FLT10(fbScaleHost.ValueOut);

(* Host AI2: температура в камере (ПВТ110, 4-20 мА, −40…+80 °C) *)
fbScaleHost(AINum := 2, SType := STYPE_4_20MA, Min := -400, Max := 800);
fbAMSet(iNum := 24, xState := fbScaleHost.ErrWire); (* обрыв 4-20 мА, t камеры *)
AI_fTChamber := FLT10(fbScaleHost.ValueOut);

(* Host AI3: влажность в камере (ПВТ110, 4-20 мА, 5…95 %) *)
fbScaleHost(AINum := 3, SType := STYPE_4_20MA, Min := 50, Max := 950);
fbAMSet(iNum := 25, xState := fbScaleHost.ErrWire); (* обрыв 4-20 мА, влажность *)
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
   ЧАСТЬ 2. ТРЕВОГИ ALARMMANAGER V212 (код бывшего FB_ALARMS)
   ════════════════════════════════════════════════════════════════
   - регистрация условий 34 тревог (FB_AM_SET) — нумерация 0–33, план §5;
   - сводные флаги: g_xAnyAlarm (FB_AM_HAS_ALARMS), g_xAnyBlock (FB_AM_IS_BLOCK);
   - упаковка тревог для HMI: D550 (биты 0–15), D551 (биты 16–31), D552 (биты 32–33);
   - сброс: ручной (кнопка HMI g_xAlarmResetHmi) и автосброс
     (g_xAutoReset = TRUE, через g_iAutoResetDelay минут).

   Полярности входов (проверить при пусконаладке, см. вопросы §1.3):
   - концевики клапанов «закрыт» — контакт НО: «закрыт» = вход 1,
     «не закрыт» = вход 0 (тревоги 28–33);
   - концевики клапанов «открыт» — плк.txt указывает НО («открыт» = вход 1,
     «не открыт» = вход 0), но тревоги 1–6 ниже всё ещё закодированы под
     прежнюю НЗ-полярность — привести к НО после подтверждения на стенде;
   - РД-ДД200 — контакт НЗ: «поток есть» = вход 0, «нет потока» = вход 1.

   Обрывы host-датчиков (23–25) регистрируются по fbScaleHost.ErrWire
   СРАЗУ после масштабирования в части 1 и здесь НЕ повторяются.
   Обрыв щупов Pt100 (19–22) — по значению ≤ −1900 (модуль L02-RTD
   контроля обрыва не имеет, см. план §4, п.5).
 *)

(* ── Регистрация условий тревог ───────────────────────────────── *)
(* 0: реле контроля фаз — ошибка фазировки *)
fbAMSet(iNum := 0, xState := DI_PhaseFault);

(* 1–6:клапан не открылся — командв «открыть» подана,
   а концевик «открыт» (НО) не сработал. НО: DI_*Open = 1 — клапан открыт,
   0 — закрыт.*)
fbAMSet(iNum := 1, xState := DO_VlvIn1Open AND NOT DI_VlvIn1Open);
fbAMSet(iNum := 2, xState := DO_VlvIn2Open AND NOT DI_VlvIn2Open);
fbAMSet(iNum := 3, xState := DO_VlvOut1Open AND NOT DI_VlvOut1Open);
fbAMSet(iNum := 4, xState := DO_VlvOut2Open AND NOT DI_VlvOut2Open);
fbAMSet(iNum := 5, xState := DO_VlvRec1Open AND NOT DI_VlvRec1Open);
fbAMSet(iNum := 6, xState := DO_VlvRec2Open AND NOT DI_VlvRec2Open);

(* 28–33: клапан не закрылся — команды «открыть» нет (пружина закрывает),
   а концевик «закрыт» (НО) не сработал. НО: DI_*Close = 1 — клапан закрыт,
   0 — не закрыт.*)
fbAMSet(iNum := 28, xState := NOT DO_VlvIn1Open AND NOT DI_VlvIn1Close);
fbAMSet(iNum := 29, xState := NOT DO_VlvIn2Open AND NOT DI_VlvIn2Close);
fbAMSet(iNum := 30, xState := NOT DO_VlvOut1Open AND NOT DI_VlvOut1Close);
fbAMSet(iNum := 31, xState := NOT DO_VlvOut2Open AND NOT DI_VlvOut2Close);
fbAMSet(iNum := 32, xState := NOT DO_VlvRec1Open AND NOT DI_VlvRec1Close);
fbAMSet(iNum := 33, xState := NOT DO_VlvRec2Open AND NOT DI_VlvRec2Close);

(* 7–12: нет потока воздуха, напорные вентиляторы 1–6 *)
fbAMSet(iNum := 7, xState := DO_FanH1 AND DI_Flow1);
fbAMSet(iNum := 8, xState := DO_FanH2 AND DI_Flow2);
fbAMSet(iNum := 9, xState := DO_FanH3 AND DI_Flow3);
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

(* 19–22: обрыв Pt100 — щупы продукта 1–4 (значение ≤ −190 °C).
   Модуль L02-RTD выдаёт ГОТОВУЮ температуру в R23700…R23703 (INT, °C×10) —
   сравниваем её напрямую (без перевода в REAL), тип INT совпадает. *)
fbAMSet(iNum := 19, xState := R23700 <= -1900);
fbAMSet(iNum := 20, xState := R23701 <= -1900);
fbAMSet(iNum := 21, xState := R23702 <= -1900);
fbAMSet(iNum := 22, xState := R23703 <= -1900);

(* 26: температура продукта выше максимума (любой из 4 щупов) —
   сравнение по готовым значениям модуля R23700…R23703 (INT, °C×10) *)
fbAMSet(iNum := 26, xState := (R23700 > g_iTprodMax) OR
                              (R23701 > g_iTprodMax) OR
                              (R23702 > g_iTprodMax) OR
                              (R23703 > g_iTprodMax));

(* 27: влажность ниже минимума (исключая обрыв 4-20 мА).
   AI_fHChamber — REAL в натуральных единицах (FLT10 делит на 10),
   g_iHmin — INT в масштабе ×10 → порог переводится функцией FLT10
   (в GX Works 2 нет неявного REAL↔INT в сравнениях). *)
fbAMSet(iNum := 27, xState := AI_fHChamber < FLT10(g_iHmin));

(* ── Сводные флаги для логики и HMI ──────────────────────────── *)
fbAMHas(iProcessNum := 0, iSeverity := 0, Q := g_xAnyAlarm, AC := g_iAlarmCount);
fbAMBlock(iProcessNum := 0, iSeverity := 0, Q := g_xAnyBlock);

(* ── Упаковка тревог для HMI: D550 (0–15), D551 (16–31), D552 (32–33) ── *)
fbAMPack(DNUM := 3000, PD := c_AM_PACK_M);

(* ── Сброс тревог ────────────────────────────────────────────── *)
(* FB_AM_RESET удерживает сигнал сброса 1 с (см. AlarmManager V212) *)
fbAMReset(IN := g_xAlarmResetHmi, AutoReset := g_iAutoResetDelay * 60);

(* ════════════════════════════════════════════════════════════════
   ЧАСТЬ 3. СВЕТОВАЯ КОЛОННА (ФБ FB_LIGHT)
   ════════════════════════════════════════════════════════════════
   Выбор режима и индикация по плану §6.7. FB_LIGHT — единственный
   оставшийся в проекте функциональный блок (кроме библиотечных).
 *)
fbLight();


(* Состояние вентияторов
0=выкл, 1=вкл, 2=тревога *)
g_iFun1State := 0;
MOV(DO_FanH1, 1, g_iFun1State);
MOV(AM_ALARMS[13].Alarm, 2, g_iFun1State);

g_iFun2State := 0;
MOV(DO_FanH2, 1, g_iFun2State);
MOV(AM_ALARMS[14].Alarm, 2, g_iFun2State);

g_iFun3State := 0;
MOV(DO_FanH3, 1, g_iFun3State);
MOV(AM_ALARMS[15].Alarm, 2, g_iFun3State);

g_iFun4State := 0;
MOV(DO_FanH4, 1, g_iFun4State);
MOV(AM_ALARMS[16].Alarm, 2, g_iFun4State);

g_iFun5State := 0;
MOV(DO_FanH5, 1, g_iFun5State);
MOV(AM_ALARMS[17].Alarm, 2, g_iFun5State);

g_iFun6State := 0;
MOV(DO_FanH6, 1, g_iFun6State);
MOV(AM_ALARMS[18].Alarm, 2, g_iFun6State);

g_iFun7State := 0;
MOV(DO_FanR1, 1, g_iFun7State);

g_iFun8State := 0;
MOV(DO_FanR2, 1, g_iFun8State);

g_iFun9State := 0;
MOV(DO_FanR3, 1, g_iFun9State);

g_iFun10State := 0;
MOV(DO_FanR4, 1, g_iFun10State);

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
xMbDummy := MB_SLAVE_INIT_PORT2(M8002 OR g_xMbApply, g_iMbAddr, PortSettings);
