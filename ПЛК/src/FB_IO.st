(*
  FB_IO — слой аналоговых входов (FB)
  - host AI0:  температура улицы, датчик 0-10 В (D8030), диапазон −50…+50 °C
               → °C×10, обрыв — по ErrWire (g_xErrTout);
  - host AI2:  температура в камере, ПВТ110 4-20 мА (D8032),
               диапазон −40…+80 °C → °C×10;
  - host AI3:  влажность в камере, ПВТ110 4-20 мА (D8033),
               диапазон 5…95 % → %×10;
  - модуль L02-RTD: щупы продукта 1–4 (R23700–R23703) — готовые °C×10;
  - средняя температура продукта по 4 щупам.

  Коррекция датчиков (настройки HMI, °C×10):
  - g_iCorrTout — датчик улицы;
  - g_iCorrTprod1..4 — щупы продукта 1–4.
  Значение Correction прибавляется к результату (см. Utils V3).

  Контроль обрыва 4-20 мА выполняется в FB_ALARMS по СЫРЫМ значениям
  host-входов (метки AI_RAW_TChamber/AI_RAW_HChamber, т.е. D8032/D8033,
  значение ≥ 32720). Масштабированные значения пишутся в метки AI_*
  (D0–D7), которые читают остальные ФБ и HMI.

  Один экземпляр SCALE_AI используется для всех host-каналов,
  один экземпляр L02_SCALE_AI — для всех щупов (см. Utils V3).

  Экземпляр ФБ: fbIO (PRG_MAIN.csv). Локальные переменные — в FB_IO.csv.
*)

(* Host AI0: температура улицы, датчик 0-10 В (−50…+50 °C → −500…+500 °C×10).
   Обрыв провода — ErrWire: сохраняем сразу после вызова, т.к. экземпляр
   fbScaleHost общий для 3 каналов и ErrWire перезапишется ниже. *)
fbScaleHost(AINum := 0, SType := STYPE_0_10V, Min := -500, Max := 500,
            Correction := g_iCorrTout, FilterTime := 10, FilterNum := 100,
            ValueOut := AI_TOutside);
g_xErrTout := fbScaleHost.ErrWire;

(* Host AI2: температура в камере (ПВТ110, 4-20 мА, −40…+80 °C) *)
fbScaleHost(AINum := 2, SType := STYPE_4_20MA, Min := -400, Max := 800,
            Correction := 0, FilterTime := 10, FilterNum := 100,
            ValueOut := AI_TChamber);

(* Host AI3: влажность в камере (ПВТ110, 4-20 мА, 5…95 %) *)
fbScaleHost(AINum := 3, SType := STYPE_4_20MA, Min := 50, Max := 950,
            Correction := 0, FilterTime := 10, FilterNum := 100,
            ValueOut := AI_HChamber);

(* L02-RTD: щупы температуры продукта 1–4 (готовые °C×10,
   контроль обрыва модулем не выполняется — детекция по значению) *)
fbScaleRtd(AINum := 0, SType := STYPE_PT100, Correction := g_iCorrTprod1,
           ValueOut := AI_TProd1);
fbScaleRtd(AINum := 1, SType := STYPE_PT100, Correction := g_iCorrTprod2,
           ValueOut := AI_TProd2);
fbScaleRtd(AINum := 2, SType := STYPE_PT100, Correction := g_iCorrTprod3,
           ValueOut := AI_TProd3);
fbScaleRtd(AINum := 3, SType := STYPE_PT100, Correction := g_iCorrTprod4,
           ValueOut := AI_TProd4);

(* Средняя температура продукта (для HMI, D7) *)
AI_TProdAvg := (AI_TProd1 + AI_TProd2 + AI_TProd3 + AI_TProd4) / 4;
