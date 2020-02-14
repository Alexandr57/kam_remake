unit KM_GUIMapEdMenuSettings;
{$I KaM_Remake.inc}
interface
uses
   Classes, SysUtils,
   KM_Controls, KM_Defaults;

type
  TKMMapEdMenuSettings = class
  private
    fOnDone: TNotifyEvent;
    procedure Back_Click(Sender: TObject);
    procedure Menu_Settings_Change(Sender: TObject);
  protected
    Panel_Settings: TKMPanel;
      TrackBar_Settings_Brightness: TKMTrackBar;
      TrackBar_Settings_SFX: TKMTrackBar;
      TrackBar_Settings_Music: TKMTrackBar;
      TrackBar_Settings_ScrollSpeed: TKMTrackBar;
      CheckBox_Settings_MusicOff: TKMCheckBox;
      CheckBox_Settings_ShuffleOn: TKMCheckBox;
      Button_Cancel: TKMButton;
  public
    constructor Create(aParent: TKMPanel; aOnDone: TNotifyEvent);

    procedure Menu_Settings_Fill;
    procedure Show;
    procedure Hide;
    function Visible: Boolean;
  end;


implementation
uses
  KM_GameApp, KM_ResTexts, KM_RenderUI, KM_ResFonts, KM_InterfaceGame, KM_Sound;


{ TKMMapEdMenuQuit }
constructor TKMMapEdMenuSettings.Create(aParent: TKMPanel; aOnDone: TNotifyEvent);
const
  PAD = 9;
  WID = TB_MAP_ED_WIDTH - 9;
begin
  inherited Create;

  fOnDone := aOnDone;

  Panel_Settings := TKMPanel.Create(aParent, 0, 44, aParent.Width, 332);
  Panel_Settings.Anchors := [anLeft, anTop, anBottom];

    with TKMLabel.Create(Panel_Settings, 9, PAGE_TITLE_Y, Panel_Settings.Width - 9, 30, gResTexts[TX_MENU_SETTINGS], fntOutline, taLeft) do
      Anchors := [anLeft, anTop, anBottom, anRight];
    TrackBar_Settings_Brightness := TKMTrackBar.Create(Panel_Settings,PAD,40,WID,0,20);
    TrackBar_Settings_Brightness.Anchors := [anLeft, anTop, anBottom, anRight];
    TrackBar_Settings_Brightness.Caption := gResTexts[TX_MENU_OPTIONS_BRIGHTNESS];
    TrackBar_Settings_Brightness.OnChange := Menu_Settings_Change;
    TrackBar_Settings_ScrollSpeed := TKMTrackBar.Create(Panel_Settings,PAD,95,WID,0,20);
    TrackBar_Settings_ScrollSpeed.Anchors := [anLeft, anTop, anBottom, anRight];
    TrackBar_Settings_ScrollSpeed.Caption := gResTexts[TX_MENU_OPTIONS_SCROLL_SPEED];
    TrackBar_Settings_ScrollSpeed.OnChange := Menu_Settings_Change;
    TrackBar_Settings_SFX := TKMTrackBar.Create(Panel_Settings,PAD,150,WID,0,20);
    TrackBar_Settings_SFX.Anchors := [anLeft, anTop, anBottom, anRight];
    TrackBar_Settings_SFX.Caption := gResTexts[TX_MENU_SFX_VOLUME];
    TrackBar_Settings_SFX.Hint := gResTexts[TX_MENU_SFX_VOLUME_HINT];
    TrackBar_Settings_SFX.OnChange := Menu_Settings_Change;
    TrackBar_Settings_Music := TKMTrackBar.Create(Panel_Settings,PAD,205,WID,0,20);
    TrackBar_Settings_Music.Anchors := [anLeft, anTop, anBottom, anRight];
    TrackBar_Settings_Music.Caption := gResTexts[TX_MENU_MUSIC_VOLUME];
    TrackBar_Settings_Music.Hint := gResTexts[TX_MENU_MUSIC_VOLUME_HINT];
    TrackBar_Settings_Music.OnChange := Menu_Settings_Change;
    CheckBox_Settings_MusicOff := TKMCheckBox.Create(Panel_Settings,PAD,260,WID,20,gResTexts[TX_MENU_OPTIONS_MUSIC_DISABLE_SHORT],fntMetal);
    CheckBox_Settings_MusicOff.Anchors := [anLeft, anTop, anBottom, anRight];
    CheckBox_Settings_MusicOff.Hint := gResTexts[TX_MENU_OPTIONS_MUSIC_DISABLE_HINT];
    CheckBox_Settings_MusicOff.OnClick := Menu_Settings_Change;
    CheckBox_Settings_MusicOff.Anchors := [anLeft, anTop, anBottom, anRight];
    CheckBox_Settings_ShuffleOn := TKMCheckBox.Create(Panel_Settings,PAD,285,WID,20,gResTexts[TX_MENU_OPTIONS_MUSIC_SHUFFLE_SHORT],fntMetal);
    CheckBox_Settings_ShuffleOn.Hint := gResTexts[TX_MENU_OPTIONS_MUSIC_SHUFFLE_HINT];
    CheckBox_Settings_ShuffleOn.OnClick := Menu_Settings_Change;

    Button_Cancel := TKMButton.Create(Panel_Settings, PAD, 310, WID, 30, gResTexts[TX_MENU_DONT_QUIT_MISSION], bsGame);
    Button_Cancel.Anchors := [anLeft, anTop, anBottom, anRight];

    Button_Cancel.Hint := gResTexts[TX_MENU_DONT_QUIT_MISSION];
    Button_Cancel.OnClick := Back_Click;
end;


procedure TKMMapEdMenuSettings.Menu_Settings_Fill;
begin
  TrackBar_Settings_Brightness.Position   := gGameApp.GameSettings.Brightness;
  TrackBar_Settings_ScrollSpeed.Position  := gGameApp.GameSettings.ScrollSpeed;
  TrackBar_Settings_SFX.Position          := Round(gGameApp.GameSettings.SoundFXVolume * TrackBar_Settings_SFX.MaxValue);
  TrackBar_Settings_Music.Position        := Round(gGameApp.GameSettings.MusicVolume * TrackBar_Settings_Music.MaxValue);
  CheckBox_Settings_MusicOff.Checked      := gGameApp.GameSettings.MusicOff;
  CheckBox_Settings_ShuffleOn.Checked     := gGameApp.GameSettings.ShuffleOn;

  TrackBar_Settings_Music.Enabled     := not CheckBox_Settings_MusicOff.Checked;
  CheckBox_Settings_ShuffleOn.Enabled := not CheckBox_Settings_MusicOff.Checked;
end;


procedure TKMMapEdMenuSettings.Menu_Settings_Change(Sender: TObject);
var
  MusicToggled, ShuffleToggled: Boolean;
begin
  //Change these options only if they changed state since last time
  MusicToggled   := (gGameApp.GameSettings.MusicOff <> CheckBox_Settings_MusicOff.Checked);
  ShuffleToggled := (gGameApp.GameSettings.ShuffleOn <> CheckBox_Settings_ShuffleOn.Checked);

  gGameApp.GameSettings.Brightness    := TrackBar_Settings_Brightness.Position;
  gGameApp.GameSettings.ScrollSpeed   := TrackBar_Settings_ScrollSpeed.Position;
  gGameApp.GameSettings.SoundFXVolume := TrackBar_Settings_SFX.Position / TrackBar_Settings_SFX.MaxValue;
  gGameApp.GameSettings.MusicVolume   := TrackBar_Settings_Music.Position / TrackBar_Settings_Music.MaxValue;
  gGameApp.GameSettings.MusicOff      := CheckBox_Settings_MusicOff.Checked;
  gGameApp.GameSettings.ShuffleOn     := CheckBox_Settings_ShuffleOn.Checked;

  gSoundPlayer.UpdateSoundVolume(gGameApp.GameSettings.SoundFXVolume);
  gGameApp.MusicLib.UpdateMusicVolume(gGameApp.GameSettings.MusicVolume);
  if MusicToggled then
  begin
    gGameApp.MusicLib.ToggleMusic(not gGameApp.GameSettings.MusicOff);
    if not gGameApp.GameSettings.MusicOff then
      ShuffleToggled := True; //Re-shuffle songs if music has been enabled
  end;
  if ShuffleToggled then
    gGameApp.MusicLib.ToggleShuffle(gGameApp.GameSettings.ShuffleOn);

  TrackBar_Settings_Music.Enabled := not CheckBox_Settings_MusicOff.Checked;
  CheckBox_Settings_ShuffleOn.Enabled := not CheckBox_Settings_MusicOff.Checked;
end;


procedure TKMMapEdMenuSettings.Back_Click(Sender: TObject);
begin
  fOnDone(Self);
end;


procedure TKMMapEdMenuSettings.Hide;
begin
  Panel_Settings.Hide;
end;


procedure TKMMapEdMenuSettings.Show;
begin
  Panel_Settings.Show;
end;


function TKMMapEdMenuSettings.Visible: Boolean;
begin
  Result := Panel_Settings.Visible;
end;


end.
