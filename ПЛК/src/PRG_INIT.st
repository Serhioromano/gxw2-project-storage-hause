(*
  INIT — отдельная программа однократной инициализации (Program)
  ЗАПУСКАЕТСЯ ОДИН РАЗ при старте ПЛК (первый скан / M8002 в настройках
  задачи). НЕ вызывается из MAIN и НЕ оборачивается в IF M8002.
  Если задача запускается циклически — вернуть обёртку IF M8002,
  иначе настройки и AM_INIT будут выполняться каждый скан.

  Содержимое:
  - настройки по умолчанию — применяются ТОЛЬКО если текущее значение = 0
    (первый старт / после сброса регистров); изменения с HMI сохраняются
    между перезапусками ПЛК;
  - AlarmManager V203: конфигурация 28 тревог (AM_INIT), AM_ALARMS_NUM := 28;
  - (задел) Modbus slave для диспетчеризации/PUSH — по умолчанию отключён.

  Применение IP-адреса (L02_SET_IP) вынесено в MAIN — там обрабатывается
  и кнопка «Применить IP» (M524). IP ПЛК: D520–D523.

  Локальные переменные — в PRG_INIT.csv (класс VAR, Program).
*)

(* Разрешение прерываний (EI) — первая строка каждой программы *)
EI(TRUE);

(* ── Настройки по умолчанию (ТЗ §8.5) ───────────────────────
   Правило: уставка проставляется ТОЛЬКО если текущее значение = 0
   И сама уставка > 0. Это значит, что настройки, изменённые оператором
   с HMI, сохраняются между перезапусками ПЛК; заводские значения
   применяются лишь при первом старте (или после сброса D-регистров).
   Следствие: уставку нельзя сознательно задать равной 0 (например,
   ToutMin = 0.0 °C) — при перезапуске она вернётся к заводскому
   значению. Для уставок по умолчанию 0 (TprodMax, Hmin, коррекции)
   запись не выполняется вообще — они остаются как есть. *)

IF g_iIntensity = 0 THEN g_iIntensity := 1; END_IF;   (* 600 мин рециркуляции *)
IF g_iToutMin = 0 THEN g_iToutMin := 30; END_IF;      (* 3.0 °C — мин. t улицы *)
IF g_iToutMax = 0 THEN g_iToutMax := 250; END_IF;     (* 25.0 °C — макс. t улицы *)
IF g_iTpreheat = 0 THEN g_iTpreheat := 50; END_IF;    (* 5.0 °C — подогрев заслонок *)
IF g_iPreheatTime = 0 THEN g_iPreheatTime := 180; END_IF; (* 180 с — предподогрев *)
IF g_iStartDelay = 0 THEN g_iStartDelay := 3; END_IF;    (* 3 с — пуск вентиляторов *)
IF g_iManualAspMin = 0 THEN g_iManualAspMin := 5; END_IF; (* 5 мин — ручн. аспирация *)
(* g_xAutoReset: BOOL, заводское FALSE — не трогаем; выбор оператора
   (вкл/выкл) сохраняется между перезапусками. *)
IF g_iAutoResetDelay = 0 THEN g_iAutoResetDelay := 60; END_IF; (* 60 мин — автосброс *)
(* g_iTprodMax, g_iHmin: заводская уставка 0, задаётся оператором с HMI —
   не перезаписываем, иначе нельзя сохранить 0 (запрет тревог). *)
(* Коррекция датчиков Pt100 (HMI, °C×10): заводская уставка 0 —
   не перезаписываем (настройка оператора). *)
(* IP-адрес ПЛК — задаётся при пусконаладке с HMI (D520–D523);
   заводские октеты применяются только если октет = 0. *)

(* ── AlarmManager V203: конфигурация тревог (28 шт.) ────────
   Нумерация 0–27, задержки в единицах 50 мс (тик TCO_TICKER_50).
   См. план §5. *)
AM_ALARMS_NUM := 28;

(* 0: реле контроля фаз — Error, мгновенно, блокирующая (стоп моторов) *)
fbAMInit(iNum := 0, iSeverity := AM_ERROR, iProcess := 1, iDelay := 0,
         xLock := TRUE, xLatch := FALSE, xBuzzer := FALSE);

(* 1–6: клапан не открылся — Warning, 60 с (iDelay 1200 × 50 мс) *)
fbAMInit(iNum := 1, iSeverity := AM_WARNING, iProcess := 1, iDelay := 1200,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 2, iSeverity := AM_WARNING, iProcess := 1, iDelay := 1200,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 3, iSeverity := AM_WARNING, iProcess := 1, iDelay := 1200,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 4, iSeverity := AM_WARNING, iProcess := 1, iDelay := 1200,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 5, iSeverity := AM_WARNING, iProcess := 1, iDelay := 1200,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 6, iSeverity := AM_WARNING, iProcess := 1, iDelay := 1200,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);

(* 7–12: нет потока воздуха, напорный вентилятор — Error, 30 с (iDelay 600 × 50 мс) *)
fbAMInit(iNum := 7, iSeverity := AM_ERROR, iProcess := 1, iDelay := 600,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 8, iSeverity := AM_ERROR, iProcess := 1, iDelay := 600,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 9, iSeverity := AM_ERROR, iProcess := 1, iDelay := 600,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 10, iSeverity := AM_ERROR, iProcess := 1, iDelay := 600,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 11, iSeverity := AM_ERROR, iProcess := 1, iDelay := 600,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 12, iSeverity := AM_ERROR, iProcess := 1, iDelay := 600,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);

(* 13–18: пускатель напорного не замкнулся — Error, 3 с, ЗАЩЁЛКА (iDelay 60 × 50 мс) *)
fbAMInit(iNum := 13, iSeverity := AM_ERROR, iProcess := 1, iDelay := 60,
         xLock := FALSE, xLatch := TRUE, xBuzzer := FALSE);
fbAMInit(iNum := 14, iSeverity := AM_ERROR, iProcess := 1, iDelay := 60,
         xLock := FALSE, xLatch := TRUE, xBuzzer := FALSE);
fbAMInit(iNum := 15, iSeverity := AM_ERROR, iProcess := 1, iDelay := 60,
         xLock := FALSE, xLatch := TRUE, xBuzzer := FALSE);
fbAMInit(iNum := 16, iSeverity := AM_ERROR, iProcess := 1, iDelay := 60,
         xLock := FALSE, xLatch := TRUE, xBuzzer := FALSE);
fbAMInit(iNum := 17, iSeverity := AM_ERROR, iProcess := 1, iDelay := 60,
         xLock := FALSE, xLatch := TRUE, xBuzzer := FALSE);
fbAMInit(iNum := 18, iSeverity := AM_ERROR, iProcess := 1, iDelay := 60,
         xLock := FALSE, xLatch := TRUE, xBuzzer := FALSE);

(* 19–22: обрыв Pt100 щупы продукта 1–4 — Warning, 3 с (iDelay 60 × 50 мс) *)
fbAMInit(iNum := 19, iSeverity := AM_WARNING, iProcess := 1, iDelay := 60,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 20, iSeverity := AM_WARNING, iProcess := 1, iDelay := 60,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 21, iSeverity := AM_WARNING, iProcess := 1, iDelay := 60,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 22, iSeverity := AM_WARNING, iProcess := 1, iDelay := 60,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);

(* 23: обрыв датчика улицы (0-10 В) — Warning, 3 с (iDelay 60 × 50 мс) *)
fbAMInit(iNum := 23, iSeverity := AM_WARNING, iProcess := 1, iDelay := 60,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);

(* 24–25: обрыв 4-20 мА ПВТ110 (t°, влажность) — Warning, 3 с (iDelay 60 × 50 мс) *)
fbAMInit(iNum := 24, iSeverity := AM_WARNING, iProcess := 1, iDelay := 60,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 25, iSeverity := AM_WARNING, iProcess := 1, iDelay := 60,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);

(* 26: температура продукта выше макс. — Error, 5 с (iDelay 100 × 50 мс) *)
fbAMInit(iNum := 26, iSeverity := AM_ERROR, iProcess := 1, iDelay := 100,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);

(* 27: влажность ниже минимума — Error, 5 с (iDelay 100 × 50 мс) *)
fbAMInit(iNum := 27, iSeverity := AM_ERROR, iProcess := 1, iDelay := 100,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);


