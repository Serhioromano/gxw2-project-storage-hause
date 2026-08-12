(*
  FB_ACTUATORS — приводы и исполнительные механизмы (FB)
  - напорные вентиляторы Y06–Y13 (6 шт.);
  - разгонные вентиляторы Y02–Y05 (4 шт., 220 В);
  - клапаны Belimo Y24–Y31 (питание = открыть, пружина = закрыть);
  - подогрев заслонок Y20–Y23 (4 ТЭН);
  - блокировка охладителя Y00 (1 = запрет охлаждения, 0 = разрешение).

  Особенности:
  - в режиме «Рециркуляция» (g_iModeDisp = 1) все вентиляторы следуют
    за охладителем X20 (ТЗ §7.3.1);
  - блокирующая тревога «реле фаз» (g_xAnyBlock) снимает команды
    вентиляторов («останов всех двигателей», план §5);
  - в «Продувке» вентиляторами управляет оператор вручную — команды
    автомата в этом режиме равны FALSE (см. FB_PROCESS, состояние IDLE).

  Экземпляр ФБ: fbActuators (MAIN.csv). Локальных переменных нет
  (FB_ACTUATORS.csv содержит только заголовок).
*)

(* ── Вентиляторы: команда автомата, блокировка при реле фаз ───── *)
DO_FanH1 := g_xCmdFanH1 AND NOT g_xAnyBlock;
DO_FanH2 := g_xCmdFanH2 AND NOT g_xAnyBlock;
DO_FanH3 := g_xCmdFanH3 AND NOT g_xAnyBlock;
DO_FanH4 := g_xCmdFanH4 AND NOT g_xAnyBlock;
DO_FanH5 := g_xCmdFanH5 AND NOT g_xAnyBlock;
DO_FanH6 := g_xCmdFanH6 AND NOT g_xAnyBlock;
DO_FanR1 := g_xCmdFanR1 AND NOT g_xAnyBlock;
DO_FanR2 := g_xCmdFanR2 AND NOT g_xAnyBlock;
DO_FanR3 := g_xCmdFanR3 AND NOT g_xAnyBlock;
DO_FanR4 := g_xCmdFanR4 AND NOT g_xAnyBlock;

(* ── Рециркуляция: вентиляторы следуют за охладителем (X20) ───── *)
IF g_iModeDisp = 1 AND NOT g_xAnyBlock THEN
    DO_FanH1 := DI_CoolerRun;
    DO_FanH2 := DI_CoolerRun;
    DO_FanH3 := DI_CoolerRun;
    DO_FanH4 := DI_CoolerRun;
    DO_FanH5 := DI_CoolerRun;
    DO_FanH6 := DI_CoolerRun;
    DO_FanR1 := DI_CoolerRun;
    DO_FanR2 := DI_CoolerRun;
    DO_FanR3 := DI_CoolerRun;
    DO_FanR4 := DI_CoolerRun;
END_IF;

(* ── Клапаны (Belimo: питание = открыть, пружина = закрыть) ───── *)
DO_VlvIn1Open := g_xCmdValveIn1;
DO_VlvIn2Open := g_xCmdValveIn2;
DO_VlvOut1Open := g_xCmdValveOut1;
DO_VlvOut2Open := g_xCmdValveOut2;
DO_VlvRec1Open := g_xCmdValveRec1;
DO_VlvRec2Open := g_xCmdValveRec2;

(* ── Подогрев заслонок приток/сброс ──────────────────────────── *)
DO_HeatVlvIn1 := g_xCmdHeatIn1;
DO_HeatVlvIn2 := g_xCmdHeatIn2;
DO_HeatVlvOut1 := g_xCmdHeatOut1;
DO_HeatVlvOut2 := g_xCmdHeatOut2;

(* ── Блокировка охладителя: 1 = запрет, 0 = разрешение ───────── *)
DO_CoolerStop := g_xCmdCoolerStop;
