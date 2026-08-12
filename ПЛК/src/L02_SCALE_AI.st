AINum := LIMITATION(0,AINum,50);
Z3 := AINum;
MOV(M8002, SType, R23500Z3);

iTemp    := R23700Z3;
ValueOut := 0;
ValueOut := SEL(
	(SType = STYPE_0_10V OR SType = STYPE_0_20MA OR SType = STYPE_4_20MA), 
	iTemp,
	SEL(
		Min = Max,
		SCALE(iTemp,0,32000,Min,Max),
		Min 
	)
) + Correction;