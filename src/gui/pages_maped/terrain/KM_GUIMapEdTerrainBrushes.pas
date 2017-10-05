unit KM_GUIMapEdTerrainBrushes;
{$I KaM_Remake.inc}
interface
uses
   Classes, Math, SysUtils,
   KM_Controls, KM_Defaults, KM_Pics, KM_ResTileset;


const
  BRUSH_MAX_SIZE = 32;

type
  //Painting on terrain with terrain brushes
  TKMMapEdTerrainBrushes = class
  private
    fLastShape: TKMMapEdShape;
    fLastBrush: Integer;
    fLastMagicBrush: Boolean;
    procedure BrushChange(Sender: TObject);
    procedure BrushRefresh;
  protected
    Panel_Brushes: TKMPanel;
    BrushSize: TKMTrackBar;
    BrushCircle: TKMButtonFlat;
    BrushSquare: TKMButtonFlat;
    BrushTable: array [0..6, 0..4] of TKMButtonFlat;
    BrushMasks: array [TKMTileMaskKind] of TKMButtonFlat;
    MagicBrush: TKMButtonFlat;
    BrushRandom: TKMCheckBox;
  public
    constructor Create(aParent: TKMPanel);

    procedure Show;
    procedure Hide;
    function Visible: Boolean;
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer; X,Y: Integer; var aHandled: Boolean);
    procedure RightClickCancel;
    procedure UpdateState;
  end;


implementation
uses
  TypInfo, KM_ResFonts, KM_ResTexts, KM_Game, KM_GameCursor, KM_RenderUI,
  KM_TerrainPainter, KM_InterfaceGame;

type
  TMBrushButtonType = (bbtBrush = -1, bbtMask = -2);


{ TKMMapEdTerrainBrushes }
constructor TKMMapEdTerrainBrushes.Create(aParent: TKMPanel);
const
  Surfaces: array [0..5, 0..4] of TKMTerrainKind = (
    (tkGrass,       tkMoss,         tkPaleGrass,    tkGrassDirt,    tkDirt),
    (tkCoastSand,   tkGrassSand1,   tkGrassSand2,   tkGrassSand3,   tkSand),
    (tkSwamp,       tkGrassyWater,  tkWater,        tkFastWater,    tkCustom),
    (tkShallowSnow, tkSnow,         tkDeepSnow,     tkIce,          tkCustom),
    (tkStone,       tkGoldMount,    tkIronMount,    tkCobbleStone,  tkGravel),
    (tkCoal,        tkGold,         tkIron,         tkLava,         tkAbyss));
var
  I,K: Integer;
  MK: TKMTileMaskKind;
  HintStr: String;
begin
  inherited Create;

  fLastShape := hsCircle;
  fLastBrush := Byte(Surfaces[0,0]);
  fLastMagicBrush := False;

  Panel_Brushes := TKMPanel.Create(aParent, 0, 28, TB_WIDTH, 400);

  TKMLabel.Create(Panel_Brushes, 0, PAGE_TITLE_Y, TB_WIDTH, 0, gResTexts[TX_MAPED_TERRAIN_BRUSH], fnt_Outline, taCenter);
  BrushSize   := TKMTrackBar.Create(Panel_Brushes, 0, 30, 100, 0, BRUSH_MAX_SIZE);
  BrushSize.Position := 4;
  BrushSize.OnChange := BrushChange;
  BrushCircle := TKMButtonFlat.Create(Panel_Brushes, 106, 28, 24, 24, 592);
  BrushCircle.Hint := gResTexts[TX_MAPED_TERRAIN_HEIGHTS_CIRCLE];
  BrushCircle.OnClick := BrushChange;
  BrushSquare := TKMButtonFlat.Create(Panel_Brushes, 134, 28, 24, 24, 593);
  BrushSquare.Hint := gResTexts[TX_MAPED_TERRAIN_HEIGHTS_SQUARE];
  BrushSquare.OnClick := BrushChange;

  for I := Low(Surfaces) to High(Surfaces) do
    for K := Low(Surfaces[I]) to High(Surfaces[I]) do
    if Surfaces[I,K] <> tkCustom then
    begin
      BrushTable[I,K] := TKMButtonFlat.Create(Panel_Brushes, K * 36, 60 + I * 40, 34, 34, Combo[Surfaces[I,K], Surfaces[I,K], 1] + 1, rxTiles);
      BrushTable[I,K].Tag := Byte(Surfaces[I,K]);
      BrushTable[I,K].Tag2 := Byte(bbtBrush);
      HintStr := GetEnumName(TypeInfo(TKMTerrainKind), Integer(Surfaces[I,K]));
      BrushTable[I,K].Hint := Copy(HintStr, 3, Length(HintStr) - 2);
      BrushTable[I,K].OnClick := BrushChange;
    end;

  BrushRandom := TKMCheckBox.Create(Panel_Brushes, 0, 310, TB_WIDTH, 20, gResTexts[TX_MAPED_TERRAIN_BRUSH_RANDOM], fnt_Metal);
  BrushRandom.OnClick := BrushChange;
  BrushRandom.Hint := 'Use random elements while drawing'; //Todo translate

  for MK := Low(TKMTileMaskKind) to High(TKMTileMaskKind) do
  begin
    BrushMasks[MK] := TKMButtonFlat.Create(Panel_Brushes, Byte(MK) * 36, 340, 34, 34, TILE_MASK_KINDS_PREVIEW[MK] + 1, rxTiles);
    BrushMasks[MK].Tag := Byte(MK);
    BrushMasks[MK].Tag2 := Byte(bbtMask);
    if MK = mk_None then
      HintStr := 'No mask'
    else begin
      HintStr := GetEnumName(TypeInfo(TKMTileMaskKind), Integer(MK));
      HintStr := Copy(HintStr, 4, Length(HintStr) - 3) + ' mask'; //Todo translate
    end;
    BrushMasks[MK].Hint := HintStr;
    BrushMasks[MK].OnClick := BrushChange;
  end;

  BrushMasks[mk_Hard3].Hide;

  MagicBrush := TKMButtonFlat.Create(Panel_Brushes, 36*4, 340, 34, 34, 668, rxGui);
  MagicBrush.Hint := 'Magic brush - automatically fix all tile transitions with chosen mask'; //Todo translate
  MagicBrush.OnClick := BrushChange;
end;


procedure TKMMapEdTerrainBrushes.BrushChange(Sender: TObject);
begin
  if gGameCursor.Mode <> cmBrush then
    gGameCursor.Mode := cmBrush;    // This will reset Tag

  gGameCursor.MapEdSize := BrushSize.Position;
  gGame.MapEditor.TerrainPainter.RandomizeTiling := BrushRandom.Checked;

  if Sender = MagicBrush then
  begin
    gGameCursor.MapEdMagicBrush := True;
    fLastMagicBrush := True;
  end else
  begin
    if Sender = BrushCircle then
    begin
      gGameCursor.MapEdShape := hsCircle;
      fLastShape := hsCircle;
    end
    else
    if Sender = BrushSquare then
    begin
      gGameCursor.MapEdShape := hsSquare;
      fLastShape := hsSquare;
    end
    else
    if Sender is TKMButtonFlat then
    begin
      if TKMButtonFlat(Sender).Tag2 = Byte(bbtBrush) then
      begin
        gGameCursor.Tag1 := TKMButtonFlat(Sender).Tag;
        fLastBrush := TKMButtonFlat(Sender).Tag;
        fLastMagicBrush := False;
        gGameCursor.MapEdMagicBrush := False;
      end else
        gGameCursor.MapEdBrushMask := TKMButtonFlat(Sender).Tag;
    end;
  end;

  BrushRefresh;
end;


procedure TKMMapEdTerrainBrushes.BrushRefresh;
var
  I,K: Integer;
  MK: TKMTileMaskKind;
begin
  BrushCircle.Down := (gGameCursor.MapEdShape = hsCircle);
  BrushSquare.Down := (gGameCursor.MapEdShape = hsSquare);
  MagicBrush.Down  := gGameCursor.MapEdMagicBrush;
  for I := Low(BrushTable) to High(BrushTable) do
    for K := Low(BrushTable[I]) to High(BrushTable[I]) do
      if gGameCursor.MapEdMagicBrush then
      begin
        if BrushTable[I,K] <> nil then
          BrushTable[I,K].Down := False;
      end else
        if BrushTable[I,K] <> nil then
          BrushTable[I,K].Down := (BrushTable[I,K].Tag = gGameCursor.Tag1);

  for MK := Low(TKMTileMaskKind) to High(TKMTileMaskKind) do
    BrushMasks[MK].Down := (BrushMasks[MK].Tag = gGameCursor.MapEdBrushMask);
end;


procedure TKMMapEdTerrainBrushes.Hide;
begin
  Panel_Brushes.Hide;
end;


procedure TKMMapEdTerrainBrushes.Show;
begin
  if gGameCursor.Mode <> cmBrush then
    gGameCursor.Mode := cmBrush;    // This will reset Tag

  gGameCursor.MapEdShape := fLastShape;
  gGameCursor.MapEdMagicBrush := fLastMagicBrush;
  if fLastBrush >= 0 then
    gGameCursor.Tag1 := fLastBrush;

  BrushChange(nil);

  Panel_Brushes.Show;
end;


function TKMMapEdTerrainBrushes.Visible: Boolean;
begin
  Result := Panel_Brushes.Visible;
end;


procedure TKMMapEdTerrainBrushes.MouseWheel(Shift: TShiftState; WheelDelta, X, Y: Integer; var aHandled: Boolean);
begin
  aHandled := False;
  if ssCtrl in Shift then
  begin
    BrushSize.Position := Max(0, BrushSize.Position - (WheelDelta div 100)); //can't set negative number
    BrushChange(nil);
    aHandled := True;
  end;
end;


procedure TKMMapEdTerrainBrushes.RightClickCancel;
begin
  // Reset last object on RMB click
  if gGameCursor.Mode = cmBrush then
  begin
    fLastShape := hsCircle;
    fLastBrush := -1;
    fLastMagicBrush := False;
  end;
end;


procedure TKMMapEdTerrainBrushes.UpdateState;
begin
  BrushRefresh;
end;


end.
