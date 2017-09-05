unit KM_Saves;
{$I KaM_Remake.inc}
interface
uses
  Classes, KromUtils, Math, Windows, SysUtils, SyncObjs,
  {$IFDEF FPC}FileUtil,{$ENDIF}
  {$IFDEF WDC}IOUtils,{$ENDIF}
  KM_CommonClasses, KM_Defaults, KM_GameInfo, KM_GameOptions, KM_Minimap, KM_ResTexts, KM_Resource;


type
  TSavesSortMethod = (
    smByFileNameAsc, smByFileNameDesc,
    smByDescriptionAsc, smByDescriptionDesc,
    smByTimeAsc, smByTimeDesc,
    smByDateAsc, smByDateDesc,
    smByPlayerCountAsc, smByPlayerCountDesc,
    smByModeAsc, smByModeDesc);

  TKMSaveInfo = class;
  TSaveEvent = procedure (aSave: TKMSaveInfo) of object;

  //Savegame info, most of which is stored in TKMGameInfo structure
  TKMSaveInfo = class
  private
    fPath: string; //TKMGameInfo does not stores paths, because they mean different things for Maps and Saves
    fFileName: string; //without extension
    fCRC: Cardinal;
    fSaveError: string;
    fInfo: TKMGameInfo;
    fGameOptions: TKMGameOptions;
    procedure ScanSave;
  public
    constructor Create(const aName: String; aIsMultiplayer: Boolean);
    destructor Destroy; override;

    property Info: TKMGameInfo read fInfo;
    property GameOptions: TKMGameOptions read fGameOptions;
    property Path: string read fPath;
    property FileName: string read fFileName;
    property CRC: Cardinal read fCRC;
    property SaveError: string read fSaveError;

    function IsValid: Boolean;
    function IsMultiplayer: Boolean;
    function IsReplayValid: Boolean;
    function LoadMinimap(aMinimap: TKMMinimap): Boolean;
  end;

  TTSavesScanner = class(TThread)
  private
    fMultiplayerPath: Boolean;
    fOnSaveAdd: TSaveEvent;
    fOnSaveAddDone: TNotifyEvent;
  public
    constructor Create(aMultiplayerPath: Boolean; aOnSaveAdd: TSaveEvent; aOnSaveAddDone, aOnTerminate: TNotifyEvent);
    procedure Execute; override;
  end;

  TKMSavesCollection = class
  private
    fCount: Word;
    fSaves: array of TKMSaveInfo;
    fSortMethod: TSavesSortMethod;
    CS: TCriticalSection;
    fScanner: TTSavesScanner;
    fScanning: Boolean;
    fScanFinished: Boolean;
    fUpdateNeeded: Boolean;
    fOnRefresh: TNotifyEvent;
    fOnComplete: TNotifyEvent;
    procedure Clear;
    procedure SaveAdd(aSave: TKMSaveInfo);
    procedure SaveAddDone(Sender: TObject);
    procedure ScanTerminate(Sender: TObject);
    procedure DoSort;
    function GetSave(aIndex: Integer): TKMSaveInfo;
  public
    constructor Create(aSortMethod: TSavesSortMethod = smByFileNameDesc);
    destructor Destroy; override;

    property Count: Word read fCount;
    property SavegameInfo[aIndex: Integer]: TKMSaveInfo read GetSave; default;
    procedure Lock;
    procedure Unlock;

    class function Path(const aName: UnicodeString; aIsMultiplayer: Boolean): UnicodeString;
    class function FullPath(const aName, aExt: UnicodeString; aIsMultiplayer: Boolean): UnicodeString;

    procedure Refresh(aOnRefresh: TNotifyEvent; aMultiplayerPath: Boolean; aOnComplete: TNotifyEvent = nil);
    procedure TerminateScan;
    procedure Sort(aSortMethod: TSavesSortMethod; aOnSortComplete: TNotifyEvent);
    property SortMethod: TSavesSortMethod read fSortMethod; //Read-only because we should not change it while Refreshing
    property ScanFinished: Boolean read fScanFinished;

    function Contains(aNewName: UnicodeString): Boolean;
    procedure DeleteSave(aIndex: Integer);
    procedure MoveSave(aIndex: Integer; aName: UnicodeString);
    procedure RenameSave(aIndex: Integer; aName: UnicodeString);

    function SavesList: UnicodeString;
    procedure UpdateState;
  end;


implementation

uses
  StrUtils, KM_CommonUtils;

const
  //Save folder name by IsMultiplayer flag
  SAVE_FOLDER_IS_MP: array [Boolean] of String = (SAVES_FOLDER_NAME, SAVES_MP_FOLDER_NAME);


{ TKMSaveInfo }
constructor TKMSaveInfo.Create(const aName: String; aIsMultiplayer: Boolean);
begin
  inherited Create;
  fPath := TKMSavesCollection.Path(aName, aIsMultiplayer); //ExeDir + SAVE_FOLDER_IS_MP[aIsMultiplayer] + PathDelim + aName + PathDelim;
  fFileName := aName;
  fInfo := TKMGameInfo.Create;
  fGameOptions := TKMGameOptions.Create;

  //We could postpone this step till info is actually required
  //but we do need title and TickCount right away, so it's better just to scan it ASAP
  ScanSave;
end;


destructor TKMSaveInfo.Destroy;
begin
  fInfo.Free;
  fGameOptions.Free;
  inherited;
end;


procedure TKMSaveInfo.ScanSave;
var
  LoadStream: TKMemoryStream;
begin
  if not FileExists(fPath + fFileName + '.' + EXT_SAVE_MAIN) then
  begin
    fSaveError := 'File not exists';
    Exit;
  end;

  fCRC := Adler32CRC(fPath + fFileName + '.' + EXT_SAVE_MAIN);

  LoadStream := TKMemoryStream.Create; //Read data from file into stream
  LoadStream.LoadFromFile(fPath + fFileName + '.' + EXT_SAVE_MAIN);

  fInfo.Load(LoadStream);
  fGameOptions.Load(LoadStream);
  fSaveError := fInfo.ParseError;

  if (fSaveError = '') and (fInfo.DATCRC <> gRes.GetDATCRC) then
    fSaveError := gResTexts[TX_SAVE_UNSUPPORTED_MODS];

  if fSaveError <> '' then
    fInfo.Title := fSaveError;

  LoadStream.Free;
end;


function TKMSaveInfo.LoadMinimap(aMinimap: TKMMinimap): Boolean;
var
  LoadStream, LoadMnmStream: TKMemoryStream;
  DummyInfo: TKMGameInfo;
  DummyOptions: TKMGameOptions;
  IsMultiplayer: Boolean;
  MinimapFilePath: String;
begin
  Result := False;
  if not FileExists(fPath + fFileName + '.' + EXT_SAVE_MAIN) then Exit;

  DummyInfo := TKMGameInfo.Create;
  DummyOptions := TKMGameOptions.Create;
  LoadStream := TKMemoryStream.Create; //Read data from file into stream
  try
    LoadStream.LoadFromFile(fPath + fFileName + '.' + EXT_SAVE_MAIN);

    DummyInfo.Load(LoadStream); //We don't care, we just need to skip past it correctly
    DummyOptions.Load(LoadStream); //We don't care, we just need to skip past it correctly
    LoadStream.Read(IsMultiplayer);
    if not IsMultiplayer then
    begin
      aMinimap.LoadFromStream(LoadStream);
      Result := True;
    end else begin
      // Lets try to load Minimap for MP save
      LoadMnmStream := TKMemoryStream.Create;
      try
        try
          MinimapFilePath := fPath + fFileName + '.' + EXT_SAVE_MP_MINIMAP;
          if FileExists(MinimapFilePath) then
          begin
            LoadMnmStream.LoadFromFile(MinimapFilePath); // try to load minimap from file
            aMinimap.LoadFromStream(LoadMnmStream);
            Result := True;
          end;
        except
          // Ignore any errors, because MP minimap is optional
        end;
      finally
        LoadMnmStream.Free;
      end;
    end;

  finally
    DummyInfo.Free;
    DummyOptions.Free;
    LoadStream.Free;
  end;
end;


function TKMSaveInfo.IsValid: Boolean;
begin
  Result := FileExists(fPath + fFileName + '.' + EXT_SAVE_MAIN) and (fSaveError = '') and fInfo.IsValid(True);
end;


function TKMSaveInfo.IsMultiplayer: Boolean;
begin
  Result := GetFileDirName(Copy(fPath, 0, Length(fPath) - 1)) = SAVES_MP_FOLDER_NAME;
end;


//Check if replay files exist at location
function TKMSaveInfo.IsReplayValid: Boolean;
begin
  Result := FileExists(fPath + fFileName + '.' + EXT_SAVE_BASE) and
            FileExists(fPath + fFileName + '.' + EXT_SAVE_REPLAY);
end;


{ TKMSavesCollection }
constructor TKMSavesCollection.Create(aSortMethod: TSavesSortMethod = smByFileNameDesc);
begin
  inherited Create;
  fSortMethod := aSortMethod;
  fScanFInished := True;

  //CS is used to guard sections of code to allow only one thread at once to access them
  //We mostly don't need it, as UI should access Maps only when map events are signaled
  //it acts as a safenet mostly
  CS := TCriticalSection.Create;
end;


destructor TKMSavesCollection.Destroy;
begin
  //Terminate and release the Scanner if we have one working or finished
  TerminateScan;

  //Release TKMapInfo objects
  Clear;

  CS.Free;
  inherited;
end;


procedure TKMSavesCollection.Lock;
begin
  CS.Enter;
end;


procedure TKMSavesCollection.Unlock;
begin
  CS.Leave;
end;


procedure TKMSavesCollection.Clear;
var
  I: Integer;
begin
  Assert(not fScanning, 'Guarding from access to inconsistent data');
  for I := 0 to fCount - 1 do
    fSaves[i].Free;
  fCount := 0;
end;


function TKMSavesCollection.GetSave(aIndex: Integer): TKMSaveInfo;
begin
  //No point locking/unlocking here since we return a TObject that could be modified/freed
  //by another thread before the caller uses it.
  Assert(InRange(aIndex, 0, fCount-1));
  Result := fSaves[aIndex];
end;


function TKMSavesCollection.Contains(aNewName: UnicodeString): Boolean;
var
  I: Integer;
begin
  Result := False;

  for I := 0 to fCount - 1 do
    if LowerCase(fSaves[I].FileName) = LowerCase(aNewName) then
    begin
      Result := True;
      Exit;
    end;
end;


procedure TKMSavesCollection.DeleteSave(aIndex: Integer);
var
  I: Integer;
begin
  Lock;
  try
    Assert(InRange(aIndex, 0, fCount-1));
    {$IFDEF FPC} DeleteDirectory(fSaves[aIndex].Path, False); {$ENDIF}
    {$IFDEF WDC} TDirectory.Delete(fSaves[aIndex].Path, True); {$ENDIF}
    fSaves[aIndex].Free;
    for I := aIndex to fCount - 2 do
      fSaves[I] := fSaves[I+1]; //Move them down
    Dec(fCount);
    SetLength(fSaves, fCount);
  finally
    Unlock;
  end;
end;


procedure TKMSavesCollection.MoveSave(aIndex: Integer; aName: UnicodeString);
var
  I: Integer;
  Dest, RenamedFile: UnicodeString;
  SearchRec: TSearchRec;
  FilesToMove: TStringList;
begin
  if Trim(aName) = '' then Exit;

  FilesToMove := TStringList.Create;
  Lock;
   try
    Dest := ExeDir + SAVE_FOLDER_IS_MP[fSaves[aIndex].IsMultiplayer] + PathDelim + aName + PathDelim;
    Assert(fSaves[aIndex].Path <> Dest);
    Assert(InRange(aIndex, 0, fCount - 1));

    //Remove existing dest directory
    if DirectoryExists(Dest) then
    begin
     {$IFDEF FPC} DeleteDirectory(Dest, False); {$ENDIF}
     {$IFDEF WDC} TDirectory.Delete(Dest, True); {$ENDIF}
    end;

    //Move directory to dest
    {$IFDEF FPC} RenameFile(fSaves[aIndex].Path, Dest); {$ENDIF}
    {$IFDEF WDC} TDirectory.Move(fSaves[aIndex].Path, Dest); {$ENDIF}

    //Find all files to move in dest
    //Need to find them first, rename later, because we can possibly find files, that were already renamed, in case NewName = OldName + Smth
    FindFirst(Dest + fSaves[aIndex].FileName + '*', faAnyFile - faDirectory, SearchRec);
    repeat
      if (SearchRec.Name <> '.') and (SearchRec.Name <> '..')
        and (Length(SearchRec.Name) > Length(fSaves[aIndex].FileName)) then
        FilesToMove.Add(SearchRec.Name);
    until (FindNext(SearchRec) <> 0);
    FindClose(SearchRec);

    //Move all previously finded files
    for I := 0 to FilesToMove.Count - 1 do
    begin
       RenamedFile := Dest + aName + RightStr(FilesToMove[I], Length(SearchRec.Name) - Length(fSaves[aIndex].FileName));
       if not FileExists(RenamedFile) and (Dest + FilesToMove[I] <> RenamedFile) then
         {$IFDEF FPC} RenameFile(Dest + FilesToMove[I], RenamedFile); {$ENDIF}
         {$IFDEF WDC} TFile.Move(Dest + FilesToMove[I], RenamedFile); {$ENDIF}
    end;


    //Remove the map from our list
    fSaves[aIndex].Free;
    for I  := aIndex to fCount - 2 do
      fSaves[I] := fSaves[I + 1];
    Dec(fCount);
    SetLength(fSaves, fCount);
   finally
    Unlock;
    FilesToMove.Free;
   end;
end;


procedure TKMSavesCollection.RenameSave(aIndex: Integer; aName: UnicodeString);
begin
  MoveSave(aIndex, aName);
end;


//For private acces, where CS is managed by the caller
procedure TKMSavesCollection.DoSort;
var TempSaves: array of TKMSaveInfo;
  //Return True if items should be exchanged
  function Compare(A, B: TKMSaveInfo): Boolean;
  begin
    Result := False; //By default everything remains in place
    case fSortMethod of
      smByFileNameAsc:     Result := CompareText(A.FileName, B.FileName) < 0;
      smByFileNameDesc:    Result := CompareText(A.FileName, B.FileName) > 0;
      smByDescriptionAsc:  Result := CompareText(A.Info.GetTitleWithTime, B.Info.GetTitleWithTime) < 0;
      smByDescriptionDesc: Result := CompareText(A.Info.GetTitleWithTime, B.Info.GetTitleWithTime) > 0;
      smByTimeAsc:         Result := A.Info.TickCount < B.Info.TickCount;
      smByTimeDesc:        Result := A.Info.TickCount > B.Info.TickCount;
      smByDateAsc:         Result := A.Info.SaveTimestamp > B.Info.SaveTimestamp;
      smByDateDesc:        Result := A.Info.SaveTimestamp < B.Info.SaveTimestamp;
      smByPlayerCountAsc:  Result := A.Info.PlayerCount < B.Info.PlayerCount;
      smByPlayerCountDesc: Result := A.Info.PlayerCount > B.Info.PlayerCount;
      smByModeAsc:         Result := A.Info.MissionMode < B.Info.MissionMode;
      smByModeDesc:        Result := A.Info.MissionMode > B.Info.MissionMode;
    end;
  end;

  procedure MergeSort(left, right: integer);
  var middle, i, j, ind1, ind2: integer;
  begin
    if right <= left then
      exit;

    middle := (left+right) div 2;
    MergeSort(left, middle);
    Inc(middle);
    MergeSort(middle, right);
    ind1 := left;
    ind2 := middle;
    for i := left to right do
    begin
      if (ind1 < middle) and ((ind2 > right) or not Compare(fSaves[ind1], fSaves[ind2])) then
      begin
        TempSaves[i] := fSaves[ind1];
        Inc(ind1);
      end
      else
      begin
        TempSaves[i] := fSaves[ind2];
        Inc(ind2);
      end;
    end;
    for j := left to right do
      fSaves[j] := TempSaves[j];
  end;
begin
  SetLength(TempSaves, Length(fSaves));
  MergeSort(Low(fSaves), High(fSaves));
end;


class function TKMSavesCollection.Path(const aName: UnicodeString; aIsMultiplayer: Boolean): UnicodeString;
begin
  Result := ExeDir + SAVE_FOLDER_IS_MP[aIsMultiplayer] + PathDelim + aName + PathDelim;
end;


class function TKMSavesCollection.FullPath(const aName, aExt: UnicodeString; aIsMultiplayer: Boolean): UnicodeString;
begin
  Result := Path(aName, aIsMultiplayer) + aName + '.' + aExt;
end;


function TKMSavesCollection.SavesList: UnicodeString;
var
  I: Integer;
begin
  Lock;
  try
    Result := '';
    for I := 0 to fCount - 1 do
      Result := Result + fSaves[I].FileName + EolW;
  finally
    Unlock;
  end;
end;


procedure TKMSavesCollection.UpdateState;
begin
  if fUpdateNeeded then
  begin
    if Assigned(fOnRefresh) then
      fOnRefresh(Self);

    fUpdateNeeded := False;
  end;
end;


//For public access
//Apply new Sort within Critical Section, as we could be in the Refresh phase
//note that we need to preserve fScanning flag
procedure TKMSavesCollection.Sort(aSortMethod: TSavesSortMethod; aOnSortComplete: TNotifyEvent);
begin
  Lock;
  try
    if fScanning then
    begin
      fScanning := False;
      fSortMethod := aSortMethod;
      DoSort;
      if Assigned(aOnSortComplete) then
        aOnSortComplete(Self);
      fScanning := True;
    end
    else
    begin
      fSortMethod := aSortMethod;
      DoSort;
      if Assigned(aOnSortComplete) then
        aOnSortComplete(Self);
    end;
  finally
    Unlock;
  end;
end;


procedure TKMSavesCollection.TerminateScan;
begin
  if (fScanner <> nil) then
  begin
    fScanner.Terminate;
    fScanner.WaitFor;
    fScanner.Free;
    fScanner := nil;
    fScanning := False;
  end;
  fUpdateNeeded := False; //If the scan was terminated we should not run fOnRefresh next UpdateState
end;


//Start the refresh of maplist
procedure TKMSavesCollection.Refresh(aOnRefresh: TNotifyEvent; aMultiplayerPath: Boolean; aOnComplete: TNotifyEvent = nil);
begin
  //Terminate previous Scanner if two scans were launched consequentialy
  TerminateScan;
  Clear;

  fScanFinished := False;
  fOnRefresh := aOnRefresh;
  fOnComplete := aOnComplete;

  //Scan will launch upon create automatcally
  fScanning := True;
  fScanner := TTSavesScanner.Create(aMultiplayerPath, SaveAdd, SaveAddDone, ScanTerminate);
end;


procedure TKMSavesCollection.SaveAdd(aSave: TKMSaveInfo);
begin
  Lock;
  try
    SetLength(fSaves, fCount + 1);
    fSaves[fCount] := aSave;
    Inc(fCount);

    //Set the scanning to false so we could Sort
    fScanning := False;

    //Keep the saves sorted
    //We signal from Locked section, so everything caused by event can safely access our Saves
    DoSort;

    fScanning := True;
  finally
    Unlock;
  end;
end;


procedure TKMSavesCollection.SaveAddDone(Sender: TObject);
begin
  fUpdateNeeded := True; //Next time the GUI thread calls UpdateState we will run fOnRefresh
end;


//All saves have been scanned
//No need to resort since that was done in last SaveAdd event
procedure TKMSavesCollection.ScanTerminate(Sender: TObject);
begin
  Lock;
  try
    fScanning := False;
    fScanFinished := True;
    if Assigned(fOnComplete) then
      fOnComplete(Self);
  finally
    Unlock;
  end;
end;


{ TTSavesScanner }
//aOnSaveAdd - signal that there's new save that should be added
//aOnSaveAddDone - signal that save has been added
//aOnComplete - scan is complete
constructor TTSavesScanner.Create(aMultiplayerPath: Boolean; aOnSaveAdd: TSaveEvent; aOnSaveAddDone, aOnTerminate: TNotifyEvent);
begin
  //Thread isn't started until all constructors have run to completion
  //so Create(False) may be put in front as well
  inherited Create(False);

  Assert(Assigned(aOnSaveAdd));

  fMultiplayerPath := aMultiplayerPath;
  fOnSaveAdd := aOnSaveAdd;
  fOnSaveAddDone := aOnSaveAddDone;
  OnTerminate := aOnTerminate;
  FreeOnTerminate := False;
end;


procedure TTSavesScanner.Execute;
var
  PathToSaves: string;
  SearchRec: TSearchRec;
  Save: TKMSaveInfo;
begin
  PathToSaves := ExeDir + SAVE_FOLDER_IS_MP[fMultiplayerPath] + PathDelim;

  if not DirectoryExists(PathToSaves) then Exit;

  FindFirst(PathToSaves + '*', faDirectory, SearchRec);
  repeat
    if (SearchRec.Name <> '.') and (SearchRec.Name <> '..')
      and FileExists(TKMSavesCollection.FullPath(SearchRec.Name, EXT_SAVE_MAIN, fMultiplayerPath))
      and FileExists(TKMSavesCollection.FullPath(SearchRec.Name, EXT_SAVE_REPLAY, fMultiplayerPath))
      and FileExists(TKMSavesCollection.FullPath(SearchRec.Name, EXT_SAVE_BASE, fMultiplayerPath)) then
    begin
      Save := TKMSaveInfo.Create(SearchRec.Name, fMultiplayerPath);
      if SLOW_SAVE_SCAN then
        Sleep(50);
      fOnSaveAdd(Save);
      fOnSaveAddDone(Self);
    end;
  until (FindNext(SearchRec) <> 0) or Terminated;
  FindClose(SearchRec);
end;


end.
