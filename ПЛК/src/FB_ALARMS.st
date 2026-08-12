(*
  FB_ALARMS — тревоги AlarmManager V203 (FB)
  - регистрация условий 28 тревог (AM_SET) — нумерация 0–27, план §5;
  - сводные флаги: g_xAnyAlarm (AM_HAS_ALARM), g_xAnyBlock (AM_IS_BLOCK);
  - упаковка тревог для HMI: D550 (биты 0–15), D551 (биты 16–27);
  - сброс: ручной (кнопка HMI g_xAlarmResetHmi) и автосброс
    (g_xAutoReset = TRUE, через g_iAutoResetDelay минут).

  Полярности входов (проверить при пусконаладке, см. вопросы):
  - концевики клапанов — контакт НЗ: «открыт» = вход 0, «не открыт» = вход 1;
  - РД-ДД200 — контакт НЗ: «поток есть» = вход 0, «нет потока» = вход 1.

  Обрыв 4-20 мА ПВТ110 определяется по СЫРЫМ значениям host-входов
  (метки AI_RAW_TChamber/AI_RAW_HChamber, т.е. D8032/D8033, значение ≥ 32720).
  Масштабированные значения — в AI_TChamber/AI_HChamber (D1/D2).
  Обрыв датчика улицы (0-10 В) — по ErrWire из FB_IO (g_xErrTout, M552).
  Порог относится ТОЛЬКО к host-входам (см. план §4, п.5).

  Экземпляр ФБ: fbAlarms (PRG_MAIN.csv). Локальные переменные — в FB_ALARMS.csv.
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
fbAMSet(iNum := 19, xState := AI_TProd1 <= -1900);
fbAMSet(iNum := 20, xState := AI_TProd2 <= -1900);
fbAMSet(iNum := 21, xState := AI_TProd3 <= -1900);
fbAMSet(iNum := 22, xState := AI_TProd4 <= -1900);

(* 23: обрыв датчика улицы (0-10 В) — ErrWire из FB_IO *)
fbAMSet(iNum := 23, xState := g_xErrTout);

(* 24–25: обрыв 4-20 мА ПВТ110 (host: t° камеры, влажность, ≥ 32720) *)
fbAMSet(iNum := 24, xState := AI_RAW_TChamber >= 32720);
fbAMSet(iNum := 25, xState := AI_RAW_HChamber >= 32720);

(* 26: температура продукта выше максимума (любой из 4 щупов) *)
fbAMSet(iNum := 26, xState := (AI_TProd1 > g_iTprodMax) OR
                              (AI_TProd2 > g_iTprodMax) OR
                              (AI_TProd3 > g_iTprodMax) OR
                              (AI_TProd4 > g_iTprodMax));

(* 27: влажность ниже минимума (исключая обрыв 4-20 мА) *)
fbAMSet(iNum := 27, xState := (AI_HChamber < g_iHmin) AND
                              (AI_RAW_HChamber < 32720));

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
