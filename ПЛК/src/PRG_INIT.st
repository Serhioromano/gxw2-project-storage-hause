(*
  INIT — отдельная программа однократной инициализации (Program)
  ЗАПУСКАЕТСЯ ОДИН РАЗ при старте ПЛК (первый скан / M8002 в настройках
  задачи). НЕ вызывается из MAIN и НЕ оборачивается в IF M8002.
  Если задача запускается циклически — вернуть обёртку IF M8002,
  иначе настройки и FB_AM_INIT будут выполняться каждый скан.

  Содержимое:
  - настройки по умолчанию — применяются ТОЛЬКО если текущее значение = 0
    (первый старт / после сброса регистров); изменения с HMI сохраняются
    между перезапусками ПЛК;
  - AlarmManager V212: конфигурация 34 тревог (FB_AM_INIT); хранилище AM_ALARMS объявлено в GVL (c_AM_ALARMS_NUM = 33);
  - Modbus slave (порт 2, RS-485) инициализируется в PRG_ROUTINE (не здесь).

  IP-адрес ПЛК с HMI больше не настраивается (регистры D520–D523 упразднены —
  теперь это состояния вентиляторов g_iFun1State..g_iFun4State).

  Локальные переменные — в PRG_INIT.csv (класс VAR, Program).
*)

(* Разрешение прерываний (EI) — первая строка каждой программы *)
EI(TRUE);

D8058 := 2#0000_0000_0000_1100;


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
IF g_iToutAsper = 0 THEN g_iToutAsper := 30; END_IF;  (* 3.0 °C — мин. t улицы для аспирации *)
IF g_iToutHeat = 0 THEN g_iToutHeat := 50; END_IF;   (* 5.0 °C — мин. t улицы для подогрева заслонок *)
IF g_iPreheatTime = 0 THEN g_iPreheatTime := 3; END_IF;   (* 3 мин — предподогрев *)
IF g_iManualAspMin = 0 THEN g_iManualAspMin := 5; END_IF; (* 5 мин — ручн. аспирация *)
(* g_xAutoReset: BOOL, заводское FALSE — не трогаем; выбор оператора
   (вкл/выкл) сохраняется между перезапусками. *)
IF g_iAutoResetDelay = 0 THEN g_iAutoResetDelay := 120; END_IF; (* 60 мин — автосброс *)
(* g_iTprodMax, g_iHmin: заводская уставка 0, задаётся оператором с HMI —
   не перезаписываем, иначе нельзя сохранить 0 (запрет тревог). *)
(* Коррекция датчиков Pt100 (HMI, °C×10): заводская уставка 0 —
   не перезаписываем (настройка оператора). *)

(* Настройки Modbus slave (порт 2): заводские значения применяются
   только если текущее значение = 0; изменения с HMI сохраняются. *)
IF g_iMbAddr = 0 THEN g_iMbAddr := 1; END_IF;        (* адрес 1 *)
IF g_iValveTime = 0 THEN g_iValveTime := 120; END_IF; (* 120 с — ход клапана *)

(* ── AlarmManager V212: конфигурация тревог (34 шт.) ────────
   Нумерация 0–33, задержки в единицах 50 мс (тик TCO_TICKER_50).
   См. план §5.
   ВАЖНО (V206+): хранилище AM_ALARMS/AM_EVENTS и константы ёмкости
   c_AM_ALARMS_NUM/c_AM_EVENTS_NUM объявляет ПРИЛОЖЕНИЕ (в GVL.csv),
   библиотека их больше не резервирует — строки «AM_ALARMS_NUM := 28» нет. *)

(* 0: реле контроля фаз — Error, мгновенно, блокирующая (стоп моторов) *)
fbAMInit(iNum := 0, iSeverity := c_AM_ERROR, iProcess := 1, iDelay := 0,
         xLock := TRUE, xLatch := FALSE, xBuzzer := FALSE);

(* 1–6: клапан не открылся — Warning, 60 с (iDelay g_iValveTime (сек) / 20 = х50 мс) *)
fbAMInit(iNum := 1, iSeverity := c_AM_WARNING, iProcess := 1, iDelay := g_iValveTime / 20,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 2, iSeverity := c_AM_WARNING, iProcess := 1, iDelay := g_iValveTime / 20,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 3, iSeverity := c_AM_WARNING, iProcess := 1, iDelay := g_iValveTime / 20,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 4, iSeverity := c_AM_WARNING, iProcess := 1, iDelay := g_iValveTime / 20,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 5, iSeverity := c_AM_WARNING, iProcess := 1, iDelay := g_iValveTime / 20,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 6, iSeverity := c_AM_WARNING, iProcess := 1, iDelay := g_iValveTime / 20,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);

(* 7–12: нет потока воздуха, напорный вентилятор — Error, 30 с (iDelay 600 × 50 мс) *)
fbAMInit(iNum := 7, iSeverity := c_AM_ERROR, iProcess := 1, iDelay := 600,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 8, iSeverity := c_AM_ERROR, iProcess := 1, iDelay := 600,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 9, iSeverity := c_AM_ERROR, iProcess := 1, iDelay := 600,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 10, iSeverity := c_AM_ERROR, iProcess := 1, iDelay := 600,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 11, iSeverity := c_AM_ERROR, iProcess := 1, iDelay := 600,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 12, iSeverity := c_AM_ERROR, iProcess := 1, iDelay := 600,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);

(* 13–18: пускатель напорного не замкнулся — Error, 3 с, ЗАЩЁЛКА (iDelay 60 × 50 мс) *)
fbAMInit(iNum := 13, iSeverity := c_AM_ERROR, iProcess := 1, iDelay := 60,
         xLock := FALSE, xLatch := TRUE, xBuzzer := FALSE);
fbAMInit(iNum := 14, iSeverity := c_AM_ERROR, iProcess := 1, iDelay := 60,
         xLock := FALSE, xLatch := TRUE, xBuzzer := FALSE);
fbAMInit(iNum := 15, iSeverity := c_AM_ERROR, iProcess := 1, iDelay := 60,
         xLock := FALSE, xLatch := TRUE, xBuzzer := FALSE);
fbAMInit(iNum := 16, iSeverity := c_AM_ERROR, iProcess := 1, iDelay := 60,
         xLock := FALSE, xLatch := TRUE, xBuzzer := FALSE);
fbAMInit(iNum := 17, iSeverity := c_AM_ERROR, iProcess := 1, iDelay := 60,
         xLock := FALSE, xLatch := TRUE, xBuzzer := FALSE);
fbAMInit(iNum := 18, iSeverity := c_AM_ERROR, iProcess := 1, iDelay := 60,
         xLock := FALSE, xLatch := TRUE, xBuzzer := FALSE);

(* 19–22: обрыв Pt100 щупы продукта 1–4 — Warning, 3 с (iDelay 60 × 50 мс) *)
fbAMInit(iNum := 19, iSeverity := c_AM_WARNING, iProcess := 1, iDelay := 60,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 20, iSeverity := c_AM_WARNING, iProcess := 1, iDelay := 60,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 21, iSeverity := c_AM_WARNING, iProcess := 1, iDelay := 60,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 22, iSeverity := c_AM_WARNING, iProcess := 1, iDelay := 60,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);

(* 23: обрыв датчика улицы (0-10 В) — Warning, 3 с (iDelay 60 × 50 мс) *)
fbAMInit(iNum := 23, iSeverity := c_AM_WARNING, iProcess := 1, iDelay := 60,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);

(* 24–25: обрыв 4-20 мА ПВТ110 (t°, влажность) — Warning, 3 с (iDelay 60 × 50 мс) *)
fbAMInit(iNum := 24, iSeverity := c_AM_WARNING, iProcess := 1, iDelay := 60,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 25, iSeverity := c_AM_WARNING, iProcess := 1, iDelay := 60,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);

(* 26: температура продукта выше макс. — Error, 5 с (iDelay 100 × 50 мс) *)
fbAMInit(iNum := 26, iSeverity := c_AM_ERROR, iProcess := 1, iDelay := 100,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);

(* 27: влажность ниже минимума — Error, 5 с (iDelay 100 × 50 мс) *)
fbAMInit(iNum := 27, iSeverity := c_AM_ERROR, iProcess := 1, iDelay := 100,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);

(* 28–33: клапан не закрылся — Warning, 60 с (iDelay g_iValveTime / 20 × 50 мс) *)
fbAMInit(iNum := 28, iSeverity := c_AM_WARNING, iProcess := 1, iDelay := g_iValveTime / 20,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 29, iSeverity := c_AM_WARNING, iProcess := 1, iDelay := g_iValveTime / 20,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 30, iSeverity := c_AM_WARNING, iProcess := 1, iDelay := g_iValveTime / 20,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 31, iSeverity := c_AM_WARNING, iProcess := 1, iDelay := g_iValveTime / 20,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 32, iSeverity := c_AM_WARNING, iProcess := 1, iDelay := g_iValveTime / 20,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 33, iSeverity := c_AM_WARNING, iProcess := 1, iDelay := g_iValveTime / 20,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);


