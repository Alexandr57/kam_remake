unit KM_CityManagement;
{$I KaM_Remake.inc}
interface
uses
  Math, KM_CommonUtils, SysUtils, KM_Defaults, KM_CommonClasses, KM_Points,
  KM_AISetup, KM_ResHouses, KM_ResWares, KM_ResUnits, KM_HandStats,
  KM_CityPredictor, KM_CityBuilder, KM_CityPlanner, KM_AIArmyEvaluation;

var
  GA_MANAGER_CheckUnitCount_SerfCoef    : Single = 0.3677794933;
  GA_MANAGER_CheckUnitCount_SerfLimit   : Single = 3.057023287;

type
  TKMWarfareArr = array[WARFARE_MIN..WARFARE_MAX] of record
    Avaiable, Required: Word;
    Fraction: Single;
  end;
  TKMWarriorsDemands = array[WARRIOR_EQUIPABLE_MIN..WARRIOR_EQUIPABLE_MAX] of Integer;

  TKMCityManagement = class
  private
    fOwner: TKMHandIndex;
    fSetup: TKMHandAISetup;

    fBuilder: TKMCityBuilder;
    fPredictor: TKMCityPredictor;

    fRequiredWeapons: TKMWarfareArr;
    fWarriorsDemands: TKMWarriorsDemands;

    fBalanceText: UnicodeString;

    procedure CheckUnitCount(aTick: Cardinal);
    procedure CheckMarketplaces();
    procedure CheckStoreWares(aTick: Cardinal);
    procedure CheckExhaustedHouses();
    procedure CheckAutoRepair();

    function WeaponsBalance(): TKMWarfareArr;
    procedure OrderWeapons(aWarfare: TKMWarfareArr);

  public
    constructor Create(aPlayer: TKMHandIndex; aSetup: TKMHandAISetup);
    destructor Destroy(); override;
    procedure Save(SaveStream: TKMemoryStream);
    procedure Load(LoadStream: TKMemoryStream);
    procedure SyncLoad();

    procedure AfterMissionInit();
    procedure OwnerUpdate(aPlayer: TKMHandIndex);

    property Builder: TKMCityBuilder read fBuilder write fBuilder;
    property Predictor: TKMCityPredictor read fPredictor;
    property BalanceText: UnicodeString read fBalanceText;
    property WarriorsDemands: TKMWarriorsDemands read fWarriorsDemands;

    procedure UpdateState(aTick: Cardinal);
    procedure LogStatus(var aBalanceText: UnicodeString);

  end;


implementation
uses
  Classes, KM_Game, KM_Houses, KM_HouseCollection, KM_HouseSchool, KM_HandsCollection, KM_Hand, KM_Resource,
  KM_AIFields, KM_Units, KM_UnitsCollection, KM_NavMesh, KM_HouseMarket;


const
  LACK_OF_GOLD = 8;


{ TKMCityManagement }
constructor TKMCityManagement.Create(aPlayer: TKMHandIndex; aSetup: TKMHandAISetup);
begin
  inherited Create;

  fOwner := aPlayer;
  fSetup := aSetup;

  fPredictor := TKMCityPredictor.Create(aPlayer, aSetup);
  fBuilder := TKMCityBuilder.Create(aPlayer, fPredictor);
end;


destructor TKMCityManagement.Destroy();
begin
  fPredictor.Free;
  fBuilder.Free;

  inherited;
end;


procedure TKMCityManagement.Save(SaveStream: TKMemoryStream);
begin
  SaveStream.WriteA('CityManagement');
  SaveStream.Write(fOwner);
  SaveStream.Write(fWarriorsDemands, SizeOf(fWarriorsDemands)); // Usend for Army management -> must be saved
  //SaveStream.Write(TKMWarfareArr, SizeOf(TKMWarfareArr)); // TKMWarfareArr is just local variable which is computed in each loop

  fPredictor.Save(SaveStream);
  fBuilder.Save(SaveStream);
end;


procedure TKMCityManagement.Load(LoadStream: TKMemoryStream);
begin
  LoadStream.ReadAssert('CityManagement');
  LoadStream.Read(fOwner);
  LoadStream.Read(fWarriorsDemands, SizeOf(fWarriorsDemands));
  //LoadStream.Read(TKMWarfareArr, SizeOf(TKMWarfareArr));

  fPredictor.Load(LoadStream);
  fBuilder.Load(LoadStream);
end;


procedure TKMCityManagement.SyncLoad();
begin
  fBuilder.SyncLoad();
end;


procedure TKMCityManagement.OwnerUpdate(aPlayer: TKMHandIndex);
begin
  fOwner := aPlayer;
  fPredictor.OwnerUpdate(aPlayer);
  fBuilder.OwnerUpdate(aPlayer);
end;


procedure TKMCityManagement.AfterMissionInit();
  procedure SetWareDistribution();
  begin
    // Top priority for gold mines
    gHands[fOwner].Stats.WareDistribution[wt_Coal, htMetallurgists] := 5;
    gHands[fOwner].Stats.WareDistribution[wt_Coal, htWeaponSmithy] := 3;
    gHands[fOwner].Stats.WareDistribution[wt_Coal, htIronSmithy] := 3;
    gHands[fOwner].Stats.WareDistribution[wt_Coal, htArmorSmithy] := 3;
    gHands[fOwner].Stats.WareDistribution[wt_Wood, htArmorWorkshop] := 2;
    gHands[fOwner].Stats.WareDistribution[wt_Wood, htWeaponWorkshop] := 5;
    gHands[fOwner].Stats.WareDistribution[wt_Steel, htWeaponSmithy] := 5;
    gHands[fOwner].Stats.WareDistribution[wt_Steel, htArmorSmithy] := 5;

    gHands[fOwner].Houses.UpdateResRequest;
  end;
var
  GoldCnt, IronCnt, FieldCnt, BuildCnt: Integer;
begin
  // DELETE DEBUG DELETE DEBUG DELETE DEBUG DELETE DEBUG DELETE DEBUG DELETE DEBUG DELETE DEBUG DELETE DEBUG DELETE DEBUG DELETE DEBUG DELETE DEBUG DELETE DEBUG
  //SetKaMSeed(666);
  //gGame.GameOptions.Peacetime := 70;
  //fSetup.ApplyAgressiveBuilderSetup(True);
  // DELETE DEBUG DELETE DEBUG DELETE DEBUG DELETE DEBUG DELETE DEBUG DELETE DEBUG DELETE DEBUG DELETE DEBUG DELETE DEBUG DELETE DEBUG DELETE DEBUG DELETE DEBUG

  // Change distribution
  SetWareDistribution();
  fPredictor.AfterMissionInit();

  // Find resources around Loc and change building policy
  GoldCnt := 0;
  IronCnt := 0;
  FieldCnt := 0;
  BuildCnt := 0;
  gAIFields.Eye.ScanLocResources(GoldCnt, IronCnt, FieldCnt, BuildCnt);

  fBuilder.AfterMissionInit(GoldCnt, IronCnt, FieldCnt, BuildCnt);

  fPredictor.CityInitialization(GoldCnt, IronCnt, FieldCnt, BuildCnt);
end;


procedure TKMCityManagement.UpdateState(aTick: Cardinal);
const
  LONG_UPDATE = MAX_HANDS * 25; // 30 sec
var
  FreeWorkersCnt: Integer;
begin
  if (aTick mod MAX_HANDS = fOwner) AND fSetup.AutoBuild then
  begin
    fBalanceText := '';
    FreeWorkersCnt := 0;
    fBuilder.UpdateState(aTick, FreeWorkersCnt);
    fPredictor.UpdateState(aTick);
    if not SKIP_RENDER then
      fPredictor.LogStatus(fBalanceText);
    fBuilder.ChooseHousesToBuild(FreeWorkersCnt, aTick);
    if not SKIP_RENDER then // Builder LogStatus cannot be merged with predictor
    begin
      fBuilder.LogStatus(fBalanceText);
      LogStatus(fBalanceText);
    end;
  end;

  if (aTick mod LONG_UPDATE = fOwner) then
  begin
    CheckUnitCount(aTick);
    CheckMarketplaces();
    CheckStoreWares(aTick);
    CheckAutoRepair();
    OrderWeapons( WeaponsBalance() );
    CheckExhaustedHouses();
  end;
end;


procedure TKMCityManagement.CheckUnitCount(aTick: Cardinal);
var
  P: TKMHand;
  Stats: TKMHandStats;

  function RecruitsNeeded(aCompletedWatchtowers: Word): Integer;
  const
    RECRUIT_PEACE_DELAY = 17 * 60 * 10;
  var
    Output: Integer;
  begin
    Output := aCompletedWatchtowers;

    if (aTick + RECRUIT_PEACE_DELAY > gGame.GameOptions.Peacetime * 600)
      AND (Stats.GetHouseQty(htBarracks) > 0) then
    begin
      if fSetup.UnlimitedEquip then
      begin
        // Iron soldiers
        Inc(  Output, Min( Stats.GetWareBalance(wt_MetalArmor), Stats.GetWareBalance(wt_Arbalet) + Stats.GetWareBalance(wt_Hallebard) + Min( Stats.GetWareBalance(wt_Sword), Stats.GetWareBalance(wt_MetalShield)) )  );
        // Leather soldiers we can make
        Inc(  Output, Min( Stats.GetWareBalance(wt_Armor), Stats.GetWareBalance(wt_Bow) + Stats.GetWareBalance(wt_Pike) + Min(Stats.GetWareBalance(wt_Axe), Stats.GetWareBalance(wt_Shield)) )  );
        // Militia with leftover axes
        Inc(  Output, Max( 0, Stats.GetWareBalance(wt_Axe) - Min(Stats.GetWareBalance(wt_Armor), Stats.GetWareBalance(wt_Shield)) )  );
      end
      else
        Output := Output + 10;
    end;
    Result := Output;
  end;

  function RequiredServCount(): Integer;
  var
    I,Serfs, Cnt: Integer;
  begin
    Serfs := gHands[fOwner].Stats.GetUnitQty(ut_Serf);
    Result := Max(0, Round(gHands[fOwner].Stats.GetUnitQty(ut_Worker) - Serfs));
    Cnt := 0;
    for I := 0 to P.Units.Count - 1 do
      if not P.Units[I].IsDeadOrDying
         AND (P.Units[I] is TKMUnitSerf)
         AND (P.Units[I].IsIdle) then
        Cnt := Cnt + 1;
    // Increase count of serfs carefully (compute fraction of serfs who does not have job)
    if (Cnt < GA_MANAGER_CheckUnitCount_SerfLimit)
       AND (Cnt / (Serfs*1.0) < GA_MANAGER_CheckUnitCount_SerfCoef) then
      Result := Max( 1 + Byte(Serfs < 40) + Byte(Serfs < 60), Result);
  end;

const
  TRAINING_PRIORITY: array[0..13] of TKMUnitType = (
    ut_Miner, ut_Metallurgist, ut_StoneCutter, ut_Woodcutter, ut_Lamberjack,
    ut_Farmer, ut_AnimalBreeder, ut_Baker, ut_Butcher, ut_Fisher, ut_Smith, ut_Serf, ut_Worker, ut_Recruit
  );
var
  GoldShortage: Boolean;
  I,K,cnt: Integer;
  GoldProduced: Cardinal;
  H: TKMHouse;
  HT: TKMHouseType;
  UT: TKMUnitType;
  Schools: array of TKMHouseSchool;
  Houses: array[HOUSE_MIN..HOUSE_MAX] of Integer;
  UnitReq: array[CITIZEN_MIN..CITIZEN_MAX] of Integer;
begin
  P := gHands[fOwner];
  Stats := P.Stats;
  FillChar(UnitReq, SizeOf(UnitReq), #0); //Clear up
  FillChar(Houses, SizeOf(Houses), #0); //Clear up

  //Citizens
  // Make sure we have enough gold left for self-sufficient city
  GoldProduced := Stats.GetWaresProduced(wt_Gold);
  GoldShortage := (Stats.GetWareBalance(wt_Gold) < LACK_OF_GOLD) AND (GoldProduced = 0);
  if GoldShortage then
  begin
    UnitReq[ut_Serf] := 3; // 3x Serf
    UnitReq[ut_Worker] := Byte(fSetup.WorkerCount > 0);// 1x Worker
    UnitReq[ut_Miner] := Stats.GetHouseTotal(htCoalMine) + Stats.GetHouseTotal(htGoldMine) + Stats.GetHouseQty(htIronMine); // Miner can go into iron / gold / coal mines (idealy we need 1 gold and 1 coal but it is hard to catch it)
    UnitReq[ut_Metallurgist] := Stats.GetHouseTotal(htMetallurgists) + Stats.GetHouseQty(htIronSmithy); // Metallurgist (same problem like in case of miner)
    UnitReq[ut_Woodcutter] := Byte(Stats.GetHouseQty(htWoodcutters) > 0); // 1x Woodcutter
    UnitReq[ut_StoneCutter] := Byte(Stats.GetHouseQty(htQuary) > 0); // 1x StoneCutter
    UnitReq[ut_Lamberjack] := Byte(Stats.GetHouseQty(htSawmill) > 0); // 1x Lamberjack
  end
  //Count overall unit requirement (excluding Barracks and ownerless houses)
  else
  begin
    // We need completed houses, houses in specific stage of construction and only completed watchtowers -> we have to scan houses
    for I := 0 to gHands[fOwner].Houses.Count - 1 do
    begin
      H := gHands[fOwner].Houses[I];
      if (H <> nil) AND not H.IsDestroyed then
      begin
        if H.IsComplete then
          Inc(Houses[H.HouseType], 1)
        else if (H.BuildingProgress > 0) AND (H.HouseType <> htWatchTower) then
          Inc(Houses[H.HouseType], 1);
      end;
    end;

    for HT := HOUSE_MIN to HOUSE_MAX do
      if (gRes.Houses[HT].OwnerType <> ut_None) AND (HT <> htBarracks) then
        Inc(UnitReq[gRes.Houses[HT].OwnerType], Houses[HT]);

    UnitReq[ut_Recruit] := 0;
    UnitReq[ut_Serf] := 0;
    UnitReq[ut_Worker] := 0;
    if (Stats.GetWareBalance(wt_Gold) > LACK_OF_GOLD * 2.5) OR (GoldProduced > 0) then // Dont train servs / workers / recruits when we will be out of gold
    begin
      UnitReq[ut_Worker] :=  fSetup.WorkerCount;
      UnitReq[ut_Recruit] := RecruitsNeeded(Houses[htWatchTower]);
    end;
    if (Stats.GetWareBalance(wt_Gold) > LACK_OF_GOLD * 1.5) OR (GoldProduced > 0) then // Dont train servs / workers / recruits when we will be out of gold
      UnitReq[ut_Serf] := Stats.GetUnitQty(ut_Serf) + RequiredServCount();
  end;

  // Get required houses
  for UT := Low(UnitReq) to High(UnitReq) do
    Dec(UnitReq[UT], Stats.GetUnitQty(UT));

  // Find completed schools, decrease UnitReq by already trained citizens
  cnt := 0;
  SetLength(Schools, Stats.GetHouseQty(htSchool));
  for I := 0 to P.Houses.Count - 1 do
    if (P.Houses[I] <> nil)
       AND not (P.Houses[I].IsDestroyed)
       AND (P.Houses[I].IsComplete)
       AND (P.Houses[I].HouseType = htSchool) then
    begin
      Schools[cnt] := TKMHouseSchool(P.Houses[I]);
      if GoldShortage AND (Schools[cnt].CheckResIn(wt_Gold) = 0) then // Ignore empty schools when we are out of gold
        continue;
      for K := Schools[cnt].QueueLength - 1 downto 0 do
        if (Schools[cnt].Queue[K] <> ut_None) then
        begin
          if K = 0 then // Queue is already active
            Dec(UnitReq[ Schools[Cnt].Queue[K] ],1)
          else // Remove from Queue (it doesn't have to be actual ... when is city under attack we have to save gold)
            Schools[Cnt].RemUnitFromQueue(K);
        end;
      cnt := cnt + 1;
    end;

  //Order citizen training
  for K := Low(TRAINING_PRIORITY) to High(TRAINING_PRIORITY) do
  begin
    UT := TRAINING_PRIORITY[K];
    for I := 0 to cnt - 1 do
      if (UnitReq[UT] <= 0) then // Check unit requirements
        break
      else if (Schools[I].QueueCount <= 2) then // Order citizen, decrease unit requirement
        Dec(  UnitReq[UT], Schools[I].AddUnitToQueue( UT, Min(UnitReq[UT], 3-Schools[I].QueueCount) )  )
  end;
end;


//Check if specific woodcutters are in Fell only mode
procedure TKMCityManagement.CheckMarketplaces();
var
  RequiedCnt, AvaiableCnt: Word;
  RequiredWares, AvaiableWares: array of TKMWareType;
  procedure AddWare(aWare: TKMWareType; IsRequired: Boolean = True);
  begin
    if IsRequired then
    begin
      RequiredWares[RequiedCnt] := aWare;
      RequiedCnt := RequiedCnt + 1;
    end
    else
    begin
      AvaiableWares[AvaiableCnt] := aWare;
      AvaiableCnt := AvaiableCnt + 1;
    end;
  end;

  procedure TryBuyItem(aResFrom, aResTo: TKMWareType);
  const
    TRADE_QUANTITY = 20;
  var
    I: Integer;
    Houses: TKMHousesCollection;
    HM, IdleHM: TKMHouseMarket;
  begin
    Houses := gHands[fOwner].Houses;
    IdleHM := nil;
    for I := 0 to Houses.Count - 1 do
      if (Houses[I].HouseType = htMarketplace)
        AND Houses[I].IsComplete
        AND not Houses[I].IsDestroyed then
      begin
        HM := TKMHouseMarket(Houses[I]);
        if (TKMHouseMarket(HM).ResOrder[0] <> 0)
          AND (HM.ResTo = aResTo) then
          Exit
        else if HM.AllowedToTrade(aResFrom)
          AND HM.AllowedToTrade(aResTo)
          AND (TKMHouseMarket(HM).ResOrder[0] = 0) then
          IdleHM := HM;
      end;
    if (IdleHM <> nil) then  // AND (IdleHM.ResFrom <> aResFrom) or (IdleHM.ResTo <> aResTo) then
    begin
      //IdleHM.ResOrder[0] := 0; //First we must cancel the current trade
      IdleHM.ResFrom := aResFrom;
      IdleHM.ResTo := aResTo;
      IdleHM.ResOrder[0] := TRADE_QUANTITY; //Set the new trade
    end;
  end;
const
  SOLD_ORDER: array[0..27] of TKMWareType = (
    wt_Sausages,     wt_Wine,     wt_Fish,       wt_Bread,
    wt_Skin,         wt_Leather,  wt_Pig,
    wt_Trunk,        wt_Stone,    wt_Wood,
    wt_Shield,       wt_Axe,      wt_Pike,       wt_Bow,      wt_Armor,
    wt_MetalShield,  wt_Sword,    wt_Hallebard,  wt_Arbalet,  wt_MetalArmor,
    wt_Horse,        wt_Corn,     wt_Flour,
    wt_Steel,        wt_Gold,     wt_IronOre,    wt_Coal,     wt_GoldOre
  );
  MIN_GOLD_AMOUNT = LACK_OF_GOLD * 3;
  LACK_OF_STONE = 50;
  WARFARE_SELL_LIMIT = 20;
  SELL_LIMIT = 100;
var
  MarketCnt, I, WareCnt: Word;
begin

  MarketCnt := gHands[fOwner].Stats.GetHouseQty(htMarketplace);
  if MarketCnt = 0 then
    Exit;

  RequiedCnt := 0;
  SetLength(RequiredWares,4);
  with gHands[fOwner].Stats do
  begin
    // Gold
    if (GetHouseQty(htMetallurgists) = 0)
       AND (GetWareBalance(wt_Gold) <= LACK_OF_GOLD) then
       AddWare(wt_Gold);
    // Gold ore
    if ( fPredictor.WareBalance[wt_GoldOre].Exhaustion < 20 )
      AND ( GetWareBalance(wt_Gold) < MIN_GOLD_AMOUNT )
      AND ( GetWareBalance(wt_GoldOre) < MIN_GOLD_AMOUNT ) then
      AddWare(wt_GoldOre);
    // Coal
    if ( fPredictor.WareBalance[wt_Coal].Exhaustion < 20 )
      AND ( GetWareBalance(wt_Coal) < MIN_GOLD_AMOUNT ) then
      AddWare(wt_Coal);
    // Stone
    if (GetWareBalance(wt_Stone) < LACK_OF_STONE)
      AND (GetHouseQty(htQuary) = 0) then
      AddWare(wt_Stone);
  end;

  if RequiedCnt = 0 then
    Exit;

  AvaiableCnt := 0;
  SetLength(AvaiableWares, RequiedCnt);
  for I := 0 to Length(SOLD_ORDER) - 1 do
    if (AvaiableCnt < RequiedCnt) then
    begin
      WareCnt := gHands[fOwner].Stats.GetWareBalance( SOLD_ORDER[I] );
      if (  (SOLD_ORDER[I] in [WARFARE_MIN..WARFARE_MAX]) AND (WareCnt > WARFARE_SELL_LIMIT)  )
         OR (WareCnt > SELL_LIMIT) then
        AddWare(SOLD_ORDER[I], False);
    end;

  for I := 0 to RequiedCnt - 1 do
    if (I < AvaiableCnt) then
      TryBuyItem(AvaiableWares[I], RequiredWares[I])
  else
    break;
end;


procedure TKMCityManagement.CheckStoreWares(aTick: Cardinal);
const
  TRUNK_STORE_DELAY = 45 * 60 * 10;
  WOOD_STORE_DELAY = 60 * 60 * 10;
  STONE_STORE_DELAY = 60 * 60 * 10;
  CORN_STORE_DELAY = 60 * 60 * 10;
var
  I: Integer;
  S: TKMHouseStore;
begin
  //Iterate through all Stores and block certain wares to reduce serf usage
  for I := 0 to gHands[fOwner].Houses.Count - 1 do
    if (gHands[fOwner].Houses[I].HouseType = htStore)
      AND gHands[fOwner].Houses[I].IsComplete
      AND not gHands[fOwner].Houses[I].IsDestroyed then
    begin
      S := TKMHouseStore(gHands[fOwner].Houses[I]);

      // Materials
      S.NotAcceptFlag[wt_Trunk] := (aTick > TRUNK_STORE_DELAY); // Trunk should not be blocked because of forest cleaning
      S.NotAcceptFlag[wt_Wood] := (S.CheckResIn(wt_Wood) > 20) OR (aTick > WOOD_STORE_DELAY);// AND (Predictor.WareBalance[wt_Wood].Exhaustion > 40);
      S.NotAcceptFlag[wt_Stone] := (aTick > STONE_STORE_DELAY) OR (S.CheckResIn(wt_Stone)*2 > gHands[fOwner].Stats.GetUnitQty(ut_Worker));
      S.NotAcceptFlag[wt_Gold] := S.CheckResIn(wt_Gold) > 400; // Everyone needs as much gold as possible

      // Food - don't store food when we have enought (it will cause trafic before storehouse)
      S.NotAcceptFlag[wt_Wine] := gHands[fOwner].Stats.GetWareBalance(wt_Wine) > 100;
      S.NotAcceptFlag[wt_Sausages] := gHands[fOwner].Stats.GetWareBalance(wt_Sausages) > 100;
      S.NotAcceptFlag[wt_Bread] := gHands[fOwner].Stats.GetWareBalance(wt_Bread) > 100;
      S.NotAcceptFlag[wt_Fish] := gHands[fOwner].Stats.GetWareBalance(wt_Fish) > 100;

      // Others
      S.NotAcceptFlag[wt_GoldOre] := True;
      S.NotAcceptFlag[wt_Coal] := True;
      S.NotAcceptFlag[wt_IronOre] := gHands[fOwner].Stats.GetHouseQty(htIronSmithy) > 0;
      S.NotAcceptFlag[wt_Steel] := gHands[fOwner].Stats.GetHouseQty(htWeaponSmithy) +
                                   gHands[fOwner].Stats.GetHouseQty(htArmorSmithy) > 0;
      S.NotAcceptFlag[wt_Corn] := (aTick > CORN_STORE_DELAY);
      S.NotAcceptFlag[wt_Leather] := True;
      S.NotAcceptFlag[wt_Flour] := True;
      //Pigs and skin cannot be blocked since if swinefarm is full of one it stops working (blocks other)
      //S.NotAcceptFlag[wt_Skin] := gHands[fOwner].Stats.GetHouseQty(htTannery) > 0;
      //S.NotAcceptFlag[wt_Pig] := gHands[fOwner].Stats.GetHouseQty(htButchers) > 0;
    end;
end;


//Demolish any exhausted mines, they will be rebuilt if needed
procedure TKMCityManagement.CheckExhaustedHouses();
var
  I: Integer;
  Loc: TKMPoint;
begin
  //Wait until resource is depleted and output is empty
  for I := 0 to gHands[fOwner].Houses.Count - 1 do
  if not gHands[fOwner].Houses[I].IsDestroyed
    AND gHands[fOwner].Houses[I].ResourceDepletedMsgIssued
    AND (gHands[fOwner].Houses[I].CheckResOut(wt_All) = 0) then
  begin
    Loc := gHands[fOwner].Houses[I].Entrance;
    // Remove avoid building around coal mine
    if (gHands[fOwner].Houses[I].HouseType = htCoalMine) then
      gAIFields.Influences.RemAvoidBuilding(KMRect(Loc.X-3, Loc.Y-3, Loc.X+4, Loc.Y+2));
    // Mark house plan as exhausted
    Builder.Planner.MarkAsExhausted(gHands[fOwner].Houses[I].HouseType, Loc);
    gHands[fOwner].Houses[I].DemolishHouse(fOwner);
  end;
end;


// Allow auto repair procedure
procedure TKMCityManagement.CheckAutoRepair();
var
  I: Integer;
begin
  if (gHands[fOwner].HandType <> hndComputer) then
    Exit;
  with gHands[fOwner] do
    if gHands[fOwner].AI.ArmyManagement.Defence.CityUnderAttack then
    begin
      for I := 0 to Houses.Count - 1 do
      begin
        Houses[I].BuildingRepair := false;
        if (Houses[I].HouseType = htWatchTower) AND (Houses[I].DeliveryMode = dm_Delivery) then
          Houses[I].SetDeliveryModeInstantly(dm_Closed);
      end;
    end
    else
    begin
      for I := 0 to Houses.Count - 1 do
      begin
        Houses[I].BuildingRepair := fSetup.AutoRepair;
        if (Houses[I].HouseType = htWatchTower) AND (Houses[I].DeliveryMode = dm_Closed) then
          Houses[I].SetDeliveryModeInstantly(dm_Delivery);
      end;
    end;
end;


// Calculate weapons demand from combat AI requirements
function TKMCityManagement.WeaponsBalance(): TKMWarfareArr;
var
  EnemyEval, AllyEval: TKMArmyEval;

  procedure ComputeGroupDemands(aGT: TKMGroupType; aIronRatio: Single);
  const
    // It doesnt depends on future "optimalization" of parameters: against cav should be always good pikes etc. so this array doesnt have to be computed
    BEST_VERSUS_OPTION: array[TKMGroupType] of TKMGroupType = (gt_Melee, gt_Melee, gt_Ranged, gt_AntiHorse);
  var
    Wood, Iron: Boolean;
    I: Integer;
    EnemyAttack, EnemyDefence, MyAttack, MyDefence, AttackReq, DefenceReq: Single;
    UT: TKMUnitType;
    antiGT: TKMGroupType;
    UnitEval: TKMGroupEval;
  begin
    // Get best type of oponent and compute iron ratio
    antiGT := BEST_VERSUS_OPTION[aGT];
    Wood := False;
    Iron := False;
    for I := 1 to 3 do
    begin
      UT := AITroopTrainOrder[antiGT,I];
      if (UT <> ut_None) AND not gHands[fOwner].Locks.GetUnitBlocked(UT) then
        if (I = 1) then
          Iron := True
        else
          Wood := True;
    end;
    if Wood AND not Iron then
      aIronRatio := 0
    else if not Wood AND Iron then
      aIronRatio := 1
    else if not Wood AND not Iron then
      Exit;

    // Compute strength of specific enemy group
    with EnemyEval[aGT] do
    begin
      EnemyAttack := Attack + AttackHorse * Byte(antiGT = gt_Mounted);
      EnemyDefence := ifthen( (antiGT = gt_Ranged), DefenceProjectiles, Defence) * HitPoints;
    end;
    // Decrease strength by owner's existing units
    with AllyEval[antiGT] do
    begin
      EnemyAttack := EnemyAttack - ifthen( (aGT = gt_Ranged), DefenceProjectiles, Defence) * HitPoints;
      EnemyDefence := EnemyDefence - Attack - AttackHorse * Byte(aGT = gt_Mounted);
    end;
    // Compute unit requirements
    for I := 1 to 3 do
    begin
      UT := AITroopTrainOrder[antiGT,I];
      // Skip unit type if case that it is blocked
      if (UT = ut_None) OR gHands[fOwner].Locks.GetUnitBlocked(UT) then
        continue;
      // Calculate required count of specific unit type
      UnitEval := gAIFields.Eye.ArmyEvaluation.UnitEvaluation[UT, True];
      with UnitEval do
      begin
        MyAttack := Attack + AttackHorse * Byte(aGT = gt_Mounted);
        MyDefence := ifthen( (aGT = gt_Ranged), DefenceProjectiles, Defence) * HitPoints;
      end;
      AttackReq := EnemyAttack / MyDefence;
      DefenceReq := EnemyDefence / MyAttack;
      fWarriorsDemands[UT] := fWarriorsDemands[UT] + Max(0, Round(  Max(AttackReq, DefenceReq) * ifthen( (I = 1), aIronRatio, 1-aIronRatio )  )   );
      if (I = 2) then // In case that ut_AxeFighter is not blocked skip militia
        break;
    end;
  end;

  procedure CheckMinArmyReq();
  const
    DEFAULT_COEFICIENT = 100;
    DEFAULT_ARMY_REQUIREMENTS: array[WARRIOR_EQUIPABLE_MIN..WARRIOR_EQUIPABLE_MAX] of Word = (
      1, 1, 1, 3,//ut_Militia,      ut_AxeFighter,   ut_Swordsman,     ut_Bowman,
      3, 1, 1, 1,//ut_Arbaletman,   ut_Pikeman,      ut_Hallebardman,  ut_HorseScout,
      1//ut_Cavalry
    );
  var
    SoldierCnt: Integer;
    UT: TKMUnitType;
  begin
    SoldierCnt := 0;
    for UT := Low(fWarriorsDemands) to High(fWarriorsDemands) do
      SoldierCnt := SoldierCnt + fWarriorsDemands[UT];
    if (SoldierCnt > 30) then
      Exit;

    for UT := Low(fWarriorsDemands) to High(fWarriorsDemands) do
      if not gHands[fOwner].Locks.GetUnitBlocked(UT) then
        fWarriorsDemands[UT] := fWarriorsDemands[UT] + DEFAULT_ARMY_REQUIREMENTS[UT] * DEFAULT_COEFICIENT;
  end;
//AITroopTrainOrder: array [TKMGroupType, 1..3] of TKMUnitType = (
//  (ut_Swordsman,    ut_AxeFighter, ut_Militia),
//  (ut_Hallebardman, ut_Pikeman,    ut_None),
//  (ut_Arbaletman,   ut_Bowman,     ut_None),
//  (ut_Cavalry,      ut_HorseScout, ut_None)
//);
//UnitGroups: array [WARRIOR_MIN..WARRIOR_MAX] of TKMGroupType = (
//  gt_Melee,gt_Melee,gt_Melee, //ut_Militia, ut_AxeFighter, ut_Swordsman
//  gt_Ranged,gt_Ranged,        //ut_Bowman, ut_Arbaletman
//  gt_AntiHorse,gt_AntiHorse,  //ut_Pikeman, ut_Hallebardman,
//  gt_Mounted,gt_Mounted,      //ut_HorseScout, ut_Cavalry,
//  gt_Melee,                   //ut_Barbarian
//  //TPR Army
//  gt_AntiHorse,        //ut_Peasant
//  gt_Ranged,           //ut_Slingshot
//  gt_Melee,            //ut_MetalBarbarian
//  gt_Mounted           //ut_Horseman
//);
//TroopCost: array [ut_Militia..ut_Cavalry, 1..4] of TKMWareType = (
//  (wt_Axe,          wt_None,        wt_None,  wt_None ), //Militia
//  (wt_Shield,       wt_Armor,       wt_Axe,   wt_None ), //Axefighter
//  (wt_MetalShield,  wt_MetalArmor,  wt_Sword, wt_None ), //Swordfighter
//  (wt_Armor,        wt_Bow,         wt_None,  wt_None ), //Bowman
//  (wt_MetalArmor,   wt_Arbalet,     wt_None,  wt_None ), //Crossbowman
//  (wt_Armor,        wt_Pike,        wt_None,  wt_None ), //Lance Carrier
//  (wt_MetalArmor,   wt_Hallebard,   wt_None,  wt_None ), //Pikeman
//  (wt_Shield,       wt_Armor,       wt_Axe,   wt_Horse), //Scout
//  (wt_MetalShield,  wt_MetalArmor,  wt_Sword, wt_Horse)  //Knight
//);
//WARRIOR_EQUIPABLE_MIN = ut_Militia;
//WARRIOR_EQUIPABLE_MAX = ut_Cavalry;
//  ut_Militia,      ut_AxeFighter,   ut_Swordsman,     ut_Bowman,
//  ut_Arbaletman,   ut_Pikeman,      ut_Hallebardman,  ut_HorseScout,
//  ut_Cavalry,      ut_Barbarian,

var
  I, SmithyCnt, WorkshopCnt, ArmorCnt, Sum: Integer;
  IronRatio: Single;
  WT: TKMWareType;
  GT: TKMGroupType;
  UT: TKMUnitType;
  Warfare: TKMWarfareArr;
begin
  ArmorCnt := gHands[fOwner].Stats.GetHouseQty(htArmorSmithy) + gHands[fOwner].Stats.GetHouseQty(htArmorWorkshop);
  SmithyCnt := gHands[fOwner].Stats.GetHouseQty(htWeaponSmithy);
  WorkshopCnt := gHands[fOwner].Stats.GetHouseQty(htWeaponWorkshop);
  if (ArmorCnt + SmithyCnt + WorkshopCnt = 0) then // Save time when nothing can be produced
    Exit;
  IronRatio := 0.5;
  if (SmithyCnt + WorkshopCnt > 0) then // This will avoid to divide by zero
    IronRatio := SmithyCnt / ((SmithyCnt + WorkshopCnt)*1.0);

  // Humans may spam archers -> AI will not produce long-range support because of balancing units in team
  // So it is better to calculate AllyEval just for Owner
  //AllyEval := gAIFields.Eye.ArmyEvaluation.GetAllianceStrength(aPlayer, at_Ally);
  AllyEval := gAIFields.Eye.ArmyEvaluation.Evaluation[fOwner];
  EnemyEval := gAIFields.Eye.ArmyEvaluation.AllianceEvaluation[fOwner, at_Enemy];

  // Compute requirements of warriors
  for UT := Low(fWarriorsDemands) to High(fWarriorsDemands) do
    fWarriorsDemands[UT] := 0;
  for GT := Low(TKMGroupType) to High(TKMGroupType) do
    ComputeGroupDemands(GT, IronRatio);

  // Make sure that we always produce something
  Sum := 0;
  for UT := Low(fWarriorsDemands) to High(fWarriorsDemands) do
    Sum := Sum + fWarriorsDemands[UT];
  if (Sum < 20) then
    CheckMinArmyReq();

  // Get weapons reserves
  for WT := Low(Warfare) to High(Warfare) do
  begin
    Warfare[WT].Avaiable := gHands[fOwner].Stats.GetWareBalance(WT);
    Warfare[WT].Required := 0;
  end;

  // Get count of needed weapons
  for UT := ut_AxeFighter to WARRIOR_EQUIPABLE_MAX do // Skip militia
    for I := Low(TroopCost[UT]) to High(TroopCost[UT]) do
      if (TroopCost[UT,I] <> wt_None) then
      begin
        WT := TroopCost[UT,I];
        Warfare[WT].Required := Warfare[WT].Required + fWarriorsDemands[UT];
      end
      else
        break;

  // Calculate fraction of demands
  for WT := Low(Warfare) to High(Warfare) do
    Warfare[WT].Fraction := Warfare[WT].Avaiable / Max(1,Warfare[WT].Required);

  Result := Warfare;

  for WT := Low(fRequiredWeapons) to High(fRequiredWeapons) do
    fRequiredWeapons[WT] := Warfare[WT];
end;


// Distribute required weapons into exist houses (first will be produced the larger amount of wares)
procedure TKMCityManagement.OrderWeapons(aWarfare: TKMWarfareArr);
const
  WEAPONS_PER_A_UPDATE = 3;
  PRODUCTION_HOUSES = [htArmorSmithy, htArmorWorkshop, htWeaponSmithy, htWeaponWorkshop];
var
  I, K, MaxIdx, HouseCnt: Integer;
  MostRequired: Single;
  HT: TKMHouseType;
  WT, MaxWT: TKMWareType;
  H: TKMHouse;
begin
  MaxIdx := 0; // For compiler
  for HT in PRODUCTION_HOUSES do
  begin
    // Check house cnt
    HouseCnt := gHands[fOwner].Stats.GetHouseQty(HT);
    if (HouseCnt = 0) then
      continue;
    // Find produced ware which is the most required
    MostRequired := 1.0;
    MaxWT := wt_None;
    for I := 1 to 4 do
    begin
      WT := gRes.Houses[HT].ResOutput[I];
      if (WT <> wt_None) AND (aWarfare[WT].Fraction < MostRequired) then
      begin
        MostRequired := aWarfare[WT].Fraction;
        MaxWT := WT;
        MaxIdx := I;
      end;
    end;
    // Set order
    if (MaxWT <> wt_None) then
      for I := 0 to gHands[fOwner].Houses.Count - 1 do
        if not gHands[fOwner].Houses[I].IsDestroyed then
        begin
          H := gHands[fOwner].Houses[I];
          if (H.HouseType <> HT) then
            continue;
          for K := 1 to 4 do
            H.ResOrder[K] := 0;
          H.ResOrder[MaxIdx] := WEAPONS_PER_A_UPDATE; // With update each 1-2 minutes there is not need to calculate something more
          if (HT = htArmorWorkshop) then
            H.ResOrder[2] := 10;
        end;
  end;
end;


procedure TKMCityManagement.LogStatus(var aBalanceText: UnicodeString);
const
  COLOR_WHITE = '[$FFFFFF]';
  COLOR_RED = '[$0000FF]';
  COLOR_YELLOW = '[$00FFFF]';
  COLOR_GREEN = '[$00FF00]';
  WARFARE: array[WARFARE_MIN..WARFARE_MAX] of UnicodeString =
    ('Shield     ', 'MetalShield', 'Armor      ', 'MetalArmor', 'Axe         ', 'Sword      ',
     'Pike       ', 'Hallebard  ', 'Bow        ', 'Arbalet   ', 'Horse      ');
var
  WT: TKMWareType;
begin
  aBalanceText := aBalanceText + '||Weapons orders (weapon: avaiable, required, fraction)|';
  for WT := Low(fRequiredWeapons) to High(fRequiredWeapons) do
    with fRequiredWeapons[WT] do
      aBalanceText := aBalanceText + WARFARE[WT] + #9 + '('
                      + Format(
                         COLOR_GREEN+'%D'+COLOR_WHITE+';' + #9
                        +COLOR_RED+'%D'+COLOR_WHITE+';' + #9
                        +COLOR_YELLOW+'%.2f'+COLOR_WHITE+')|', [Avaiable, Required, Fraction]
                      );
end;

end.
