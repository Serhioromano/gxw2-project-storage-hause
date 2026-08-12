(*
  FB_LIGHT — выбор режима и световая колонна (FB)
  Режим по переключателю (приоритет — «Продувка», план §6.1):
    X00=0, X01=0 → Выключено (0)
    X00=1        → Авто (1)
    X01=1        → Продувка (3) — приоритет, даже если X00=1

  Грубый режим записывается в g_iModeCoarse (D535); детальный
  (Рециркуляция/Аспирация) формирует FB_PROCESS в g_iModeDisp (D530).

  Световая колонна по плану §6.7 (мигание — M8013, 0.5 с / 0.5 с):
    Выключено        🔴 off        🟢 off
    Продувка         🔴 on         🟢 on
    Авто-рециркуляция 🔴 миг.(трев.) 🟢 on
    Авто-аспирация   🔴 миг.(трев.) 🟢 миг.
    Тревоги (любой режим) 🔴 мигает

  Экземпляр ФБ: fbLight (PRG_MAIN.csv). Локальные переменные — в FB_LIGHT.csv.
*)

(* Идёт ли аспирация (детальный режим из FB_PROCESS, прошлый скан) *)
xAspMode := (g_iModeDisp = 2);

(* Красный: мигает при любой активной тревоге, горит в Продувке *)
IF g_xAnyAlarm THEN
    xRed := M8013;
ELSIF g_iModeCoarse = 3 THEN
    xRed := TRUE;
ELSE
    xRed := FALSE;
END_IF;

(* Зелёный *)
IF g_iModeCoarse = 3 THEN
    xGreen := TRUE;                  (* Продувка — горит постоянно *)
ELSIF g_iModeCoarse = 1 OR g_xManualAspActive THEN
    IF xAspMode THEN
        xGreen := M8013;             (* Аспирация — мигает *)
    ELSE
        xGreen := TRUE;              (* Рециркуляция — горит *)
    END_IF;
ELSE
    xGreen := FALSE;                 (* Выключено — выключена *)
END_IF;

(* Выходы световой колонны *)
DO_LampRed := xRed;
DO_LampGreen := xGreen;
