(*
  INIT — отдельная программа однократной инициализации (Program)
  ЗАПУСКАЕТСЯ ОДИН РАЗ при старте ПЛК (первый скан / M8002 в настройках
  задачи). НЕ вызывается из MAIN и НЕ оборачивается в IF M8002.
  Если задача запускается циклически — вернуть обёртку IF M8002,
  иначе настройки и AM_INIT будут выполняться каждый скан.

  Содержимое:
  - настройки по умолчанию (перезаписываются оператором с HMI);
  - AlarmManager V203: конфигурация 28 тревог (AM_INIT), AM_ALARMS_NUM := 28;
  - (задел) Modbus slave для диспетчеризации/PUSH — по умолчанию отключён.

  Применение IP-адреса (L02_SET_IP) вынесено в MAIN — там обрабатывается
  и кнопка «Применить IP» (M524). IP ПЛК: D520–D523.

  Локальные переменные — в PRG_INIT.csv (класс VAR, Program).
*)

(* Разрешение прерываний (EI) — первая строка каждой программы *)
EI(TRUE);

(* ── Настройки по умолчанию (ТЗ §8.5) ─────────────────────── *)
g_iIntensity := 1;          (* Нормально: 600 мин рециркуляции *)
g_iToutMin := 30;           (* 3.0 °C  — мин. t улицы для аспирации *)
g_iToutMax := 250;          (* 25.0 °C — макс. t улицы для аспирации *)
g_iTpreheat := 50;          (* 5.0 °C  — порог подогрева заслонок *)
g_iPreheatTime := 180;      (* 180 с   — время предподогрева (3 мин) *)
g_iStartDelay := 30;        (* 30 с    — задержка пуска вентиляторов *)
g_iManualAspMin := 5;       (* 5 мин   — ручная аспирация по умолчанию *)
g_xAutoReset := FALSE;     (* выкл — автосброс тревог по умолчанию выключен *)
g_iAutoResetDelay := 60;    (* 60 мин  — задержка до автосброса *)
g_iTprodMax := 0;           (* макс. t продукта — задаётся оператором *)
g_iHmin := 0;               (* мин. влажность — задаётся оператором *)
(* Коррекция датчиков Pt100 (настройка HMI, °C×10; по умолчанию 0) *)
g_iCorrTout := 0;           (* коррекция t улицы *)
g_iCorrTprod1 := 0;         (* коррекция щуп 1 *)
g_iCorrTprod2 := 0;         (* коррекция щуп 2 *)
g_iCorrTprod3 := 0;         (* коррекция щуп 3 *)
g_iCorrTprod4 := 0;         (* коррекция щуп 4 *)
(* IP-адрес ПЛК — задаётся при пусконаладке с HMI (D520–D523) *)
g_iIp1 := 192;
g_iIp2 := 168;
g_iIp3 := 1;
g_iIp4 := 100;

(* ── AlarmManager V203: конфигурация тревог (28 шт.) ────────
   Нумерация 0–27, задержки в единицах 100 мс. См. план §5. *)
AM_ALARMS_NUM := 28;

(* 0: реле контроля фаз — Error, мгновенно, блокирующая (стоп моторов) *)
fbAMInit(iNum := 0, iSeverity := AM_ERROR, iProcess := 1, iDelay := 0,
         xLock := TRUE, xLatch := FALSE, xBuzzer := FALSE);

(* 1–6: клапан не открылся — Warning, 60 с *)
fbAMInit(iNum := 1, iSeverity := AM_WARNING, iProcess := 1, iDelay := 600,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 2, iSeverity := AM_WARNING, iProcess := 1, iDelay := 600,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 3, iSeverity := AM_WARNING, iProcess := 1, iDelay := 600,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 4, iSeverity := AM_WARNING, iProcess := 1, iDelay := 600,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 5, iSeverity := AM_WARNING, iProcess := 1, iDelay := 600,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 6, iSeverity := AM_WARNING, iProcess := 1, iDelay := 600,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);

(* 7–12: нет потока воздуха, напорный вентилятор — Error, 30 с *)
fbAMInit(iNum := 7, iSeverity := AM_ERROR, iProcess := 1, iDelay := 300,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 8, iSeverity := AM_ERROR, iProcess := 1, iDelay := 300,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 9, iSeverity := AM_ERROR, iProcess := 1, iDelay := 300,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 10, iSeverity := AM_ERROR, iProcess := 1, iDelay := 300,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 11, iSeverity := AM_ERROR, iProcess := 1, iDelay := 300,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 12, iSeverity := AM_ERROR, iProcess := 1, iDelay := 300,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);

(* 13–18: пускатель напорного не замкнулся — Error, 3 с, ЗАЩЁЛКА *)
fbAMInit(iNum := 13, iSeverity := AM_ERROR, iProcess := 1, iDelay := 30,
         xLock := FALSE, xLatch := TRUE, xBuzzer := FALSE);
fbAMInit(iNum := 14, iSeverity := AM_ERROR, iProcess := 1, iDelay := 30,
         xLock := FALSE, xLatch := TRUE, xBuzzer := FALSE);
fbAMInit(iNum := 15, iSeverity := AM_ERROR, iProcess := 1, iDelay := 30,
         xLock := FALSE, xLatch := TRUE, xBuzzer := FALSE);
fbAMInit(iNum := 16, iSeverity := AM_ERROR, iProcess := 1, iDelay := 30,
         xLock := FALSE, xLatch := TRUE, xBuzzer := FALSE);
fbAMInit(iNum := 17, iSeverity := AM_ERROR, iProcess := 1, iDelay := 30,
         xLock := FALSE, xLatch := TRUE, xBuzzer := FALSE);
fbAMInit(iNum := 18, iSeverity := AM_ERROR, iProcess := 1, iDelay := 30,
         xLock := FALSE, xLatch := TRUE, xBuzzer := FALSE);

(* 19–22: обрыв Pt100 щупы продукта 1–4 — Warning, 3 с *)
fbAMInit(iNum := 19, iSeverity := AM_WARNING, iProcess := 1, iDelay := 30,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 20, iSeverity := AM_WARNING, iProcess := 1, iDelay := 30,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 21, iSeverity := AM_WARNING, iProcess := 1, iDelay := 30,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 22, iSeverity := AM_WARNING, iProcess := 1, iDelay := 30,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);

(* 23: обрыв датчика улицы (0-10 В) — Warning, 3 с *)
fbAMInit(iNum := 23, iSeverity := AM_WARNING, iProcess := 1, iDelay := 30,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);

(* 24–25: обрыв 4-20 мА ПВТ110 (t°, влажность) — Warning, 3 с *)
fbAMInit(iNum := 24, iSeverity := AM_WARNING, iProcess := 1, iDelay := 30,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);
fbAMInit(iNum := 25, iSeverity := AM_WARNING, iProcess := 1, iDelay := 30,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);

(* 26: температура продукта выше макс. — Error, 5 с *)
fbAMInit(iNum := 26, iSeverity := AM_ERROR, iProcess := 1, iDelay := 50,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);

(* 27: влажность ниже минимума — Error, 5 с *)
fbAMInit(iNum := 27, iSeverity := AM_ERROR, iProcess := 1, iDelay := 50,
         xLock := FALSE, xLatch := FALSE, xBuzzer := FALSE);

(*
  ── Modbus slave (ЗАДЕЛ для диспетчеризации / PUSH-интеграции) ──
  По умолчанию отключён. Для включения раскомментируйте и настройте
  адрес slave и состав регистров (буфер D400–D600, см. план §7).
  Пример (адрес 1, порт 2, 9600 8N1):
      PortSettings := MB_PORT_SETTINGS(MB_PARITY_NONE, MB_STOPBIT_1, MB_BPS_9600);
      M0 := MB_SLAVE_INIT_PORT2(TRUE, 1, PortSettings);
      fbMbProcess(mb_xEnable := TRUE, mb_iBuffer := 400);
*)
