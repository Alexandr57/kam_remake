

const
	ID_PLAYER = 0;
	AI_PLAYER_BLUE = 1;
	AI_PLAYER_GREEN = 2;

	CNT_U_SERF = 10;
	CNT_U_LABORER = 5;

	CNT_H_QUARRY = 3;
	CNT_U_STONE_MASON = CNT_H_QUARRY;

	CNT_H_WOODCUTTERS = 4;
	CNT_U_WOODCUTTER = 4;
	
	CNT_H_SAWMILL = 2;
	CNT_U_CARPENTER = 2;
	
	CNT_H_FISHERMANS = 3;
	CNT_U_FISHERMAN = 3;
	
	CNT_H_FARM = 8;
	CNT_P_FIELDS = 14;
	CNT_U_FARMER = 8;
	CNT_H_MILL = 2;
	CNT_U_BAKER = 2;

	CNT_H_BAKERY = 2;
	CNT_U_BAKER = 2;
	
	CNT_H_VINEYARD = 4;
	CNT_U_FARMER = 4;
	CNT_W_FIELDS = 10;

	CNT_H_SWINE_FARM = 2;
	CNT_U_ANIMAL_BREEDER = 2;
	
	CNT_H_BUTCHERS = 1;
	CNT_U_BUTCHER = 1;
	CNT_H_TANNERY = 1;
	CNT_U_BUTCHER = 1;
	
	CNT_H_BARRACKS = 1;
	CNT_H_WEAPONS_WORKSHOP = 1;
	CNT_H_ARMORY_WORKSHOP = 1;

var 
  NextMsg: AnsiString;
  NextTime: Integer;
  MsgShown: array [0..29] of Boolean;

  GoalID: Integer;
  
  isBuildSCHOOL, isBuildINN, isBuildQUARRY, isBuildWOODCUTTERS, isBuildSAWMILL, 
  isBuildFISHERMANS, isBuildFARM, isBuildMILL, isBuildBAKERY, isBuildVINEYARD, 
  isBuildSWINEFARM, isBuildBUTCHERS, isBuildTANNERY, isBuildBARRACKS: Boolean;

  procedure Show(aMsg, aNextMsg: Byte);
  begin
    if MsgShown[aMsg] then Exit; //Show messages only once

    Actions.ShowMsg(ID_PLAYER, '<$'+IntToStr(aMsg) + 40 +'>');
    if aNextMsg <> 0 then
    begin
      NextMsg := '<$'+IntToStr(aNextMsg)+ 40 +'>';
      NextTime := States.GameTime + 100;
    end;
    MsgShown[aMsg] := True;
  end;

procedure OnHouseBuilt(aHouseID: Integer);
begin
  if States.HouseOwner(aHouseID) <> ID_PLAYER then Exit;
  case GoalID of
    0:
    begin
      if Goals[0].Status <> gsAvailable then Exit;

      if States.HouseType(aHouseID) = HT_SCHOOL then
      begin
        UpdateGoal(0, gsDone, '', False, True, False, False);
        Actions.ShowMsgFormatted(ID_PLAYER, '<$44>', [CNT_U_SERF, CNT_U_LABORER]);
      end;
    end;
    1:
    begin
      if Goals[3].Status <> gsAvailable then Exit;

      if States.HouseType(aHouseID) = HT_INN then
      begin
        UpdateGoal(3, gsDone, '', False, True, False, False);
        UpdateGoal(4, gsAvailable, '', True, True, False, False);
        UpdateGoal(5, gsAvailable, '', True, True, False, False);
        GoalID := GoalID + 1;
      end;
    end;
    2:
    begin

    end;
  end;

  case States.HouseType(aHouseID) of
    13:
    27: Show(6,0);
    14: Show(7,0);
     9: Show(8,0);
     0: Show(9,0);
     6: Show(10,0);
     8: Show(11,0);
    22: Show(12,0);
     7: Show(13,0);
    28: Show(14,0);
    16: Show(15,0);
    24: Show(16,0);
    21: Show(17,18);
    19: Show(19,20);
    25: Show(21,0);
    20: Show(22,23);
  end;
end;

procedure	OnUnitTrained(aUnitID: Integer);
begin
  if States.UnitOwner(aUnitID) <> ID_PLAYER then Exit;

  case GoalID of
    0:
    begin
      if (Goals[0].Status = gsDone) and (Goals[1].Status = gsDone) and (Goals[2].Status = gsDone) then
      begin
        Actions.ShowMsg(ID_PLAYER, '<$45>');
        UpdateGoal(1, gsNotAvailable, '', False, False, False, False);
        UpdateGoal(2, gsNotAvailable, '', False, False, False, False);
        UpdateGoal(3, gsAvailable, '', False, True, False, False);
        GoalID := GoalID + 1;
      end;

      if Goals[1].Status <> gsAvailable then Exit;

      if States.UnitType(aUnitID) = UT_SERF then
        Goals[1].Value := Goals[1].Value + 1;

      if Goals[1].Value >= Goals[1].MaxValue then
        UpdateGoal(1, gsDone, '', False, True, False, False);

      if Goals[2].Status <> gsAvailable then Exit;

      if States.UnitType(aUnitID) = UT_WOODCUTTER then
        Goals[2].Value := Goals[2].Value + 1;

      if Goals[2].Value >= Goals[2].MaxValue then
        UpdateGoal(2, gsDone, '', False, True, False, False);
    end;
    1:

  end;
end;

procedure OnPlayerDefeated(aIndex: Integer);
begin
  if aIndex = 1 then Actions.ShowMsg(ID_PLAYER, '<$24>');
  if aIndex = 2 then Actions.ShowMsg(ID_PLAYER, '<$25>');
end;

procedure OnTick;
begin
  if States.GameTime = 160 then Actions.ShowMsg(ID_PLAYER, '<$42>');
  if States.GameTime = 340 then Actions.ShowMsg(ID_PLAYER, '<$43>');

  if States.GameTime = NextTime then Actions.ShowMsg(ID_PLAYER, NextMsg);
end;

procedure OnMissionStart;
begin
  InitGoals(ID_PLAYER, 33, 0, True);
  GoalID := 0;
  Goals[1].MaxValue := CNT_U_SERF;
  Goals[2].MaxValue := CNT_U_LABORER;
  Goals[4].MaxValue := CNT_H_QUARRY;
  Goals[5].MaxValue := CNT_U_STONE_MASON;
  UpdateGoal(0, gsAvailable, '', False, True, False, False);
  UpdateGoal(1, gsAvailable, '', True, True, False, False);
  UpdateGoal(2, gsAvailable, '', True, True, False, False);
  Actions.ShowMsg(ID_PLAYER, '<$41>');
  Actions.PlayWavAtLocationLooped(-1, 'waterfall', 0.5, 32, 65, 18);
end;